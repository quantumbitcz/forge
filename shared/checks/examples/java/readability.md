# Readability Patterns (Java)

## nesting

**Instead of:**
```java
public Report generate(ReportRequest req) {
    if (req.getDateRange() != null) {
        if (req.getDateRange().getStart().isBefore(req.getDateRange().getEnd())) {
            if (permissionService.canAccess(req.getUserId(), req.getReportType())) {
                var data = dataService.query(req);
                return reportBuilder.build(data);
            } else {
                throw new AccessDeniedException(req.getUserId());
            }
        } else {
            throw new InvalidDateRangeException(req.getDateRange());
        }
    } else {
        throw new MissingDateRangeException();
    }
}
```

**Do this:**
```java
public Report generate(ReportRequest req) {
    Objects.requireNonNull(req.getDateRange(), "dateRange is required");
    if (!req.getDateRange().getStart().isBefore(req.getDateRange().getEnd()))
        throw new InvalidDateRangeException(req.getDateRange());
    if (!permissionService.canAccess(req.getUserId(), req.getReportType()))
        throw new AccessDeniedException(req.getUserId());

    var data = dataService.query(req);
    return reportBuilder.build(data);
}
```

**Why:** Validation-first ordering turns a pyramid of nested conditions into a flat list of preconditions followed by the core logic, cutting cognitive load to read and review.

## naming

**Instead of:**
```java
public double calc(List<Txn> txns) {
    double r = 0;
    for (var t : txns) {
        if (t.getT() == 1) r += t.getA();
        else r -= t.getA();
    }
    return r;
}
```

**Do this:**
```java
public double calculateNetBalance(List<Transaction> transactions) {
    double balance = 0;
    for (var transaction : transactions) {
        if (transaction.isCredit()) balance += transaction.getAmount();
        else balance -= transaction.getAmount();
    }
    return balance;
}
```

**Why:** Full names for methods, types, and locals let new readers understand the code without context, whereas single-letter abbreviations require memorizing a private mental dictionary.

## guard-clauses

**Instead of:**
```java
public UploadResult upload(MultipartFile file, Long userId) {
    if (file != null && !file.isEmpty()) {
        if (file.getSize() <= MAX_FILE_SIZE) {
            if (ALLOWED_TYPES.contains(file.getContentType())) {
                var path = storageService.store(file, userId);
                return UploadResult.success(path);
            } else {
                return UploadResult.unsupportedType(file.getContentType());
            }
        } else {
            return UploadResult.tooLarge(file.getSize(), MAX_FILE_SIZE);
        }
    } else {
        return UploadResult.empty();
    }
}
```

**Do this:**
```java
public UploadResult upload(MultipartFile file, Long userId) {
    if (file == null || file.isEmpty())
        return UploadResult.empty();
    if (file.getSize() > MAX_FILE_SIZE)
        return UploadResult.tooLarge(file.getSize(), MAX_FILE_SIZE);
    if (!ALLOWED_TYPES.contains(file.getContentType()))
        return UploadResult.unsupportedType(file.getContentType());

    var path = storageService.store(file, userId);
    return UploadResult.success(path);
}
```

**Why:** Guard clauses move rejection logic to the top where it is immediately visible, and the remaining code runs only when all preconditions are satisfied.

## extract-method

**Instead of:**
```java
public InvoiceSummary summarize(List<Invoice> invoices) {
    var total = BigDecimal.ZERO;
    var overdue = BigDecimal.ZERO;
    var count = 0;
    for (var inv : invoices) {
        if (inv.getStatus() != InvoiceStatus.CANCELLED) {
            total = total.add(inv.getAmount());
            count++;
            if (inv.getDueDate().isBefore(LocalDate.now())
                    && inv.getStatus() != InvoiceStatus.PAID) {
                overdue = overdue.add(inv.getAmount());
            }
        }
    }
    return new InvoiceSummary(total, overdue, count);
}
```

**Do this:**
```java
public InvoiceSummary summarize(List<Invoice> invoices) {
    var active = invoices.stream()
        .filter(inv -> inv.getStatus() != InvoiceStatus.CANCELLED)
        .toList();
    return new InvoiceSummary(
        sumAmounts(active),
        sumAmounts(filterOverdue(active)),
        active.size()
    );
}

private BigDecimal sumAmounts(List<Invoice> invoices) {
    return invoices.stream().map(Invoice::getAmount).reduce(BigDecimal.ZERO, BigDecimal::add);
}

private List<Invoice> filterOverdue(List<Invoice> invoices) {
    return invoices.stream()
        .filter(inv -> inv.getDueDate().isBefore(LocalDate.now()))
        .filter(inv -> inv.getStatus() != InvoiceStatus.PAID)
        .toList();
}
```

**Why:** Extracting `sumAmounts` and `filterOverdue` turns an opaque loop with interleaved concerns into named, composable operations that are individually testable.
