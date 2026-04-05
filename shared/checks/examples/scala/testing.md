# Testing Patterns (Scala)

## scalatest-matchers

**Instead of:**
```scala
test("calculates total") {
  val cart = Cart(List(Item("A", 10), Item("B", 20)))
  assert(cart.total == 30)
  assert(cart.items.length == 2)
}
```

**Do this:**
```scala
test("calculates total for multiple items") {
  val cart = Cart(List(Item("A", 10), Item("B", 20)))

  cart.total shouldBe 30
  cart.items should have length 2
}
```

**Why:** ScalaTest matchers produce descriptive failure messages (`30 was not equal to 25`) instead of bare assertion failures. The DSL reads as an English specification.

## property-based-testing

**Instead of:**
```scala
test("reverse is involution") {
  assert("hello".reverse.reverse == "hello")
  assert("".reverse.reverse == "")
  assert("a".reverse.reverse == "a")
}
```

**Do this:**
```scala
import org.scalacheck.Prop.forAll

property("reverse is an involution") {
  forAll { (s: String) =>
    s.reverse.reverse == s
  }
}
```

**Why:** Property-based testing (ScalaCheck) generates hundreds of random inputs, finding edge cases that hand-picked examples miss. If it finds a counterexample, it shrinks it to the minimal failing input.

## fixture-traits

**Instead of:**
```scala
class UserServiceSpec extends AnyFunSuite {
  test("creates user") {
    val repo = new InMemoryUserRepo
    val service = new UserService(repo)
    service.create(User("Alice"))
    assert(repo.findByName("Alice").isDefined)
  }

  test("deletes user") {
    val repo = new InMemoryUserRepo
    val service = new UserService(repo)
    repo.save(User("Alice"))
    service.delete("Alice")
    assert(repo.findByName("Alice").isEmpty)
  }
}
```

**Do this:**
```scala
trait UserServiceFixture {
  val repo    = new InMemoryUserRepo
  val service = new UserService(repo)
}

class UserServiceSpec extends AnyFunSuite {
  test("creates user") {
    new UserServiceFixture {
      service.create(User("Alice"))
      repo.findByName("Alice") shouldBe defined
    }
  }

  test("deletes user") {
    new UserServiceFixture {
      repo.save(User("Alice"))
      service.delete("Alice")
      repo.findByName("Alice") shouldBe empty
    }
  }
}
```

**Why:** Fixture traits provide fresh, isolated state per test via anonymous class instantiation. Unlike `beforeEach`, each test gets its own instance with no shared mutable state.
