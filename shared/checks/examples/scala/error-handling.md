# Error Handling Patterns (Scala)

## either-error-handling

**Instead of:**
```scala
def parsePort(s: String): Int = {
  try {
    val port = s.toInt
    if (port < 0 || port > 65535) throw new IllegalArgumentException("out of range")
    port
  } catch {
    case _: Exception => -1  // Magic sentinel
  }
}
```

**Do this:**
```scala
def parsePort(s: String): Either[String, Int] =
  s.toIntOption match {
    case None       => Left(s"'$s' is not a number")
    case Some(port) if port < 0 || port > 65535 => Left(s"Port $port out of range")
    case Some(port) => Right(port)
  }
```

**Why:** `Either[Error, Value]` makes failure a typed return value. Callers must pattern match, preventing accidental use of sentinel values. `Either` composes with `for`-comprehensions for chaining.

## using-resource-safety

**Instead of:**
```scala
def readFile(path: String): String = {
  val source = scala.io.Source.fromFile(path)
  val content = source.mkString
  source.close()  // Skipped if mkString throws
  content
}
```

**Do this:**
```scala
import scala.util.Using

def readFile(path: String): Try[String] =
  Using(scala.io.Source.fromFile(path))(_.mkString)
```

**Why:** `Using` (Scala 2.13+) guarantees resource cleanup via `AutoCloseable`, similar to Java's try-with-resources. It returns `Try[T]`, composing naturally with other error-handling patterns.

## validated-accumulation

**Instead of:**
```scala
def validateUser(name: String, email: String, age: Int): Either[String, User] = {
  if (name.isEmpty) Left("Name required")
  else if (!email.contains("@")) Left("Invalid email")
  else if (age < 0) Left("Invalid age")
  else Right(User(name, email, age))
  // Only reports the FIRST error
}
```

**Do this:**
```scala
import cats.data.ValidatedNec
import cats.syntax.all._

def validateUser(name: String, email: String, age: Int): ValidatedNec[String, User] =
  (
    validateName(name),
    validateEmail(email),
    validateAge(age)
  ).mapN(User.apply)
```

**Why:** `ValidatedNec` accumulates all validation errors instead of short-circuiting at the first failure. Users see every issue at once rather than fixing errors one-by-one.
