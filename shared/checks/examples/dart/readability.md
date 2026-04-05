# Readability Patterns (Dart)

## pattern-matching

**Instead of:**
```dart
String describe(Object value) {
  if (value is String && value.length > 10) {
    return 'long string';
  } else if (value is int && value > 0) {
    return 'positive int';
  } else if (value is List && value.isEmpty) {
    return 'empty list';
  }
  return 'other';
}
```

**Do this:**
```dart
String describe(Object value) => switch (value) {
  String(length: > 10) => 'long string',
  int(isNegative: false) => 'positive int',
  List(isEmpty: true) => 'empty list',
  _ => 'other',
};
```

**Why:** Pattern matching (Dart 3) destructures objects inline and combines type checks with property tests in a single, exhaustive expression.

## extension-types

**Instead of:**
```dart
typedef UserId = int;  // Just an alias, no type safety

void deleteUser(int userId) { /* ... */ }
void deleteOrder(int orderId) { /* ... */ }

// Nothing prevents: deleteUser(orderId)
```

**Do this:**
```dart
extension type UserId(int value) implements int {}
extension type OrderId(int value) implements int {}

void deleteUser(UserId userId) { /* ... */ }
void deleteOrder(OrderId orderId) { /* ... */ }

// deleteUser(OrderId(42))  → compile error
```

**Why:** Extension types (Dart 3.3) wrap primitives with zero runtime cost, providing compile-time type safety that prevents accidental ID swaps.

## named-parameters

**Instead of:**
```dart
Widget buildCard(String title, String subtitle, bool elevated, Color color, double radius) {
  // ...
}
buildCard('Hello', 'World', true, Colors.blue, 8.0);
```

**Do this:**
```dart
Widget buildCard({
  required String title,
  required String subtitle,
  bool elevated = false,
  Color color = Colors.white,
  double radius = 4.0,
}) {
  // ...
}
buildCard(title: 'Hello', subtitle: 'World', elevated: true);
```

**Why:** Named parameters are self-documenting at call sites and allow safe defaults. Positional boolean and numeric arguments are unreadable without context.
