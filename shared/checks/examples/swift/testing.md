# Testing Patterns (Swift)

## xctest-setup

**Instead of:**
```swift
class UserServiceTests: XCTestCase {
    func testFetch() {
        let repo = MockUserRepo()
        let service = UserService(repo: repo)
        let user = try! service.find(id: 1)
        XCTAssertEqual(user.name, "Alice")
    }
}
```

**Do this:**
```swift
class UserServiceTests: XCTestCase {
    private var repo: MockUserRepo!
    private var sut: UserService!

    override func setUp() {
        repo = MockUserRepo()
        sut = UserService(repo: repo)
    }

    func testFindReturnsUser() throws {
        let user = try sut.find(id: 1)
        XCTAssertEqual(user.name, "Alice")
    }
}
```

**Why:** Shared `setUp` eliminates duplicated construction across tests and `throws` replaces `try!` so failures produce diagnostics instead of crashes.

## swift-testing

**Instead of:**
```swift
func testDiscountValues() {
    XCTAssertEqual(discount(for: .student), 0.2)
    XCTAssertEqual(discount(for: .senior), 0.15)
    XCTAssertEqual(discount(for: .veteran), 0.1)
}
```

**Do this:**
```swift
@Test(arguments: [
    (.student, 0.2),
    (.senior, 0.15),
    (.veteran, 0.1),
])
func discount(tier: Tier, expected: Double) {
    #expect(discount(for: tier) == expected)
}
```

**Why:** Parameterized `@Test` runs each case independently so a single failure does not mask the rest, and adding cases requires no new code.

## async-test

**Instead of:**
```swift
func testFetchProfile() {
    let exp = expectation(description: "fetch")
    service.fetchProfile { result in
        if case .success(let p) = result {
            XCTAssertEqual(p.name, "Alice")
        }
        exp.fulfill()
    }
    waitForExpectations(timeout: 5)
}
```

**Do this:**
```swift
func testFetchProfile() async throws {
    let profile = try await service.fetchProfile()
    XCTAssertEqual(profile.name, "Alice")
}
```

**Why:** Async test functions replace expectation boilerplate with linear assertions, and `throws` surfaces errors directly.

## mock-protocols

**Instead of:**
```swift
class UserService {
    let repo = UserRepository()

    func find(id: Int) throws -> User {
        try repo.fetch(id)
    }
}
```

**Do this:**
```swift
protocol UserRepo {
    func fetch(_ id: Int) throws -> User
}

struct UserService {
    let repo: UserRepo

    func find(id: Int) throws -> User {
        try repo.fetch(id)
    }
}
```

**Why:** Injecting a protocol lets tests substitute a mock without touching production code or the network.
