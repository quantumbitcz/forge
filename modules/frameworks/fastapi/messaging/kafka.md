# FastAPI + Kafka (aiokafka)

> Async Kafka producer/consumer patterns for FastAPI using aiokafka with lifespan events and DI.

## Integration Setup

```bash
pip install aiokafka
```

## Framework-Specific Patterns

### Lifespan: producer and consumer startup/shutdown
```python
# app/lifespan.py
from contextlib import asynccontextmanager
from aiokafka import AIOKafkaProducer, AIOKafkaConsumer
from fastapi import FastAPI
import asyncio, json

producer: AIOKafkaProducer | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global producer
    producer = AIOKafkaProducer(
        bootstrap_servers=settings.KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    await producer.start()

    consumer_task = asyncio.create_task(_consume())
    yield

    await producer.stop()
    consumer_task.cancel()
    try:
        await consumer_task
    except asyncio.CancelledError:
        pass

async def _consume():
    consumer = AIOKafkaConsumer(
        "orders",
        bootstrap_servers=settings.KAFKA_BOOTSTRAP_SERVERS,
        group_id="fastapi-consumer",
        value_deserializer=lambda v: json.loads(v.decode()),
        auto_offset_reset="earliest",
    )
    await consumer.start()
    try:
        async for msg in consumer:
            await handle_message(msg.value)
    finally:
        await consumer.stop()
```

### Producer dependency
```python
# app/dependencies.py
from fastapi import Depends
from app.lifespan import producer as _producer
from aiokafka import AIOKafkaProducer

async def get_producer() -> AIOKafkaProducer:
    if _producer is None:
        raise RuntimeError("Kafka producer not initialized")
    return _producer
```

### Publishing from a route
```python
# app/routers/orders.py
from fastapi import APIRouter, Depends
from aiokafka import AIOKafkaProducer
from app.dependencies import get_producer

router = APIRouter()

@router.post("/orders")
async def create_order(order: OrderCreate, producer: AIOKafkaProducer = Depends(get_producer)):
    saved = await order_service.create(order)
    await producer.send_and_wait("orders", {"event": "order.created", "id": str(saved.id)})
    return saved
```

## Scaffolder Patterns
```
app/
  lifespan.py           # producer init + background consumer task
  dependencies.py       # get_producer DI helper
  handlers/
    order_handler.py    # async message handler functions
  routers/
    orders.py           # routes that publish events
main.py                 # FastAPI(lifespan=lifespan)
```

## Dos
- Initialize producer/consumer inside `lifespan` — not at module level — so they respect startup/shutdown
- Use `send_and_wait` for at-least-once delivery guarantees; use `send` for fire-and-forget
- Deserialize messages with error handling; skip and log rather than crashing the consumer loop
- Set `group_id` explicitly to enable consumer group rebalancing

## Don'ts
- Don't create a new `AIOKafkaProducer` per request — reuse the lifespan-scoped instance
- Don't block the event loop inside the consumer's async for loop; offload CPU work to a thread pool
- Don't use `auto_commit` without understanding at-least-once vs. exactly-once semantics
- Don't swallow deserialization errors silently — log and send to a dead-letter topic
