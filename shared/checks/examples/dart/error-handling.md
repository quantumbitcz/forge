# Error Handling Patterns (Dart)

## sealed-result-type

**Instead of:**
```dart
Future<User?> getUser(int id) async {
  try {
    final response = await http.get(Uri.parse('/users/$id'));
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    }
    return null;  // Caller can't distinguish "not found" from "server error"
  } catch (e) {
    return null;
  }
}
```

**Do this:**
```dart
sealed class Result<T> {}
class Success<T> extends Result<T> { final T value; Success(this.value); }
class Failure<T> extends Result<T> { final String message; Failure(this.message); }

Future<Result<User>> getUser(int id) async {
  final response = await http.get(Uri.parse('/users/$id'));
  return switch (response.statusCode) {
    200 => Success(User.fromJson(jsonDecode(response.body))),
    404 => Failure('User $id not found'),
    _ => Failure('Server error: ${response.statusCode}'),
  };
}
```

**Why:** Sealed classes (Dart 3) enable exhaustive switch expressions. Callers must handle both success and failure, and the compiler flags missing cases.

## zone-error-handling

**Instead of:**
```dart
void main() {
  runApp(MyApp());
}
// Unhandled async errors crash silently
```

**Do this:**
```dart
void main() {
  runZonedGuarded(
    () => runApp(MyApp()),
    (error, stack) {
      logger.error('Uncaught error', error: error, stackTrace: stack);
    },
  );
}
```

**Why:** `runZonedGuarded` catches uncaught async errors that would otherwise be swallowed by the event loop, ensuring they are logged and reported.

## null-aware-cascade

**Instead of:**
```dart
void configure(Settings? settings) {
  if (settings != null) {
    settings.theme = 'dark';
    settings.fontSize = 14;
    settings.save();
  }
}
```

**Do this:**
```dart
void configure(Settings? settings) {
  settings
    ?..theme = 'dark'
    ..fontSize = 14
    ..save();
}
```

**Why:** Null-aware cascades (`?..`) chain multiple operations on a nullable object in a single expression, avoiding repetitive null checks.
