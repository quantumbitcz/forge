# Readability Patterns (Scala)

## for-comprehension

**Instead of:**
```scala
def getOrderDetails(orderId: String): Option[OrderDetails] = {
  findOrder(orderId) match {
    case Some(order) =>
      findCustomer(order.customerId) match {
        case Some(customer) =>
          findAddress(customer.addressId) match {
            case Some(address) => Some(OrderDetails(order, customer, address))
            case None => None
          }
        case None => None
      }
    case None => None
  }
}
```

**Do this:**
```scala
def getOrderDetails(orderId: String): Option[OrderDetails] =
  for {
    order    <- findOrder(orderId)
    customer <- findCustomer(order.customerId)
    address  <- findAddress(customer.addressId)
  } yield OrderDetails(order, customer, address)
```

**Why:** For-comprehensions desugar to `flatMap`/`map` chains, flattening nested pattern matches into a linear pipeline. If any step returns `None`, the whole expression short-circuits.

## case-class-modeling

**Instead of:**
```scala
class Point(var x: Double, var y: Double) {
  override def equals(obj: Any): Boolean = obj match {
    case p: Point => x == p.x && y == p.y
    case _ => false
  }
  override def hashCode(): Int = (x, y).hashCode()
  override def toString: String = s"Point($x, $y)"
}
```

**Do this:**
```scala
case class Point(x: Double, y: Double)
```

**Why:** Case classes auto-generate `equals`, `hashCode`, `toString`, `copy`, and pattern matching support. They signal value-type semantics and are immutable by default.

## extension-methods

**Instead of:**
```scala
object StringUtils {
  def toSlug(s: String): String =
    s.toLowerCase.replaceAll("[^a-z0-9]+", "-").stripPrefix("-").stripSuffix("-")
}

val slug = StringUtils.toSlug(title)
```

**Do this:**
```scala
extension (s: String)
  def toSlug: String =
    s.toLowerCase.replaceAll("[^a-z0-9]+", "-").stripPrefix("-").stripSuffix("-")

val slug = title.toSlug
```

**Why:** Extension methods (Scala 3) add capabilities to existing types without inheritance or wrapper classes, making the call site read naturally as a method on the type.
