# Error Handling Patterns (C)

## errno-checking

**Instead of:**
```c
FILE *f = fopen(path, "r");
fread(buf, 1, len, f);
```

**Do this:**
```c
FILE *f = fopen(path, "r");
if (!f) {
    perror("fopen");
    return -1;
}
fread(buf, 1, len, f);
```

**Why:** Library functions signal failure through return values and `errno`; ignoring them masks I/O errors that corrupt downstream logic.

## goto-cleanup

**Instead of:**
```c
int process(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char *buf = malloc(1024);
    if (!buf) { fclose(f); return -1; }
    if (parse(buf) < 0) { free(buf); fclose(f); return -1; }
    free(buf);
    fclose(f);
    return 0;
}
```

**Do this:**
```c
int process(const char *path) {
    int rc = -1;
    FILE *f = NULL;
    char *buf = NULL;

    f = fopen(path, "r");
    if (!f) goto cleanup;
    buf = malloc(1024);
    if (!buf) goto cleanup;
    if (parse(buf) < 0) goto cleanup;
    rc = 0;

cleanup:
    free(buf);
    if (f) fclose(f);
    return rc;
}
```

**Why:** A single `cleanup` label centralizes resource release, eliminating duplicated teardown paths and the leaks that come from missing one.

## return-codes

**Instead of:**
```c
void save_record(Record *r) {
    write(fd, r, sizeof(*r));
}
```

**Do this:**
```c
int save_record(Record *r) {
    ssize_t n = write(fd, r, sizeof(*r));
    if (n < 0) return -1;
    if ((size_t)n != sizeof(*r)) return -2;
    return 0;
}
```

**Why:** Returning distinct codes lets callers distinguish between I/O failure and partial writes instead of silently losing data.

## null-check-after-malloc

**Instead of:**
```c
struct Node *node = malloc(sizeof(*node));
node->value = 42;
```

**Do this:**
```c
struct Node *node = malloc(sizeof(*node));
if (!node) {
    fprintf(stderr, "out of memory\n");
    return NULL;
}
node->value = 42;
```

**Why:** `malloc` returns `NULL` when memory is exhausted; dereferencing it without a check causes a segfault.
