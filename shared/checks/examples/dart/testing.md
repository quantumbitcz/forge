# Testing Patterns (Dart)

## widget-testing

**Instead of:**
```dart
testWidgets('shows title', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MyWidget(title: 'Hello'),
    ),
  ));
  expect(find.text('Hello'), findsOneWidget);
});
```

**Do this:**
```dart
testWidgets('displays title text from constructor', (tester) async {
  await tester.pumpWidget(
    MaterialApp(home: MyWidget(title: 'Hello')),
  );

  expect(find.text('Hello'), findsOneWidget);
});
```

**Why:** Minimal widget trees reduce test noise. Only wrap with ancestors that the widget actually needs (e.g., `MaterialApp` for Material widgets). Descriptive test names explain the expected behavior.

## mock-dependencies

**Instead of:**
```dart
test('fetches user', () async {
  // Hitting real API in tests
  final svc = UserService(ApiClient());
  final user = await svc.getUser(1);
  expect(user.name, isNotEmpty);
});
```

**Do this:**
```dart
class MockApiClient extends Mock implements ApiClient {}

test('fetches user by ID', () async {
  final api = MockApiClient();
  when(() => api.get('/users/1')).thenAnswer(
    (_) async => Response('{"name":"Alice"}', 200),
  );

  final svc = UserService(api);
  final user = await svc.getUser(1);

  expect(user.name, equals('Alice'));
  verify(() => api.get('/users/1')).called(1);
});
```

**Why:** Mocktail mocks isolate the unit under test from network dependencies, making tests fast, deterministic, and able to simulate error conditions.
