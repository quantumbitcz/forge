# Django + Kafka (confluent-kafka-python)

> Kafka integration for Django using `confluent-kafka-python`. Covers management command consumer, signal-based producer, and django-kafka patterns.

## Integration Setup

```bash
pip install confluent-kafka
# Optional higher-level abstraction:
pip install django-kafka
```

```python
# settings.py
KAFKA_BOOTSTRAP_SERVERS = env("KAFKA_BOOTSTRAP_SERVERS", default="localhost:9092")
```

## Framework-Specific Patterns

### Signal-based producer
Produce a message whenever a Django model is saved:
```python
# orders/signals.py
import json
from confluent_kafka import Producer
from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Order

_producer = Producer({"bootstrap.servers": settings.KAFKA_BOOTSTRAP_SERVERS})

@receiver(post_save, sender=Order)
def publish_order_event(sender, instance, created, **kwargs):
    event = "order.created" if created else "order.updated"
    _producer.produce(
        topic="orders",
        key=str(instance.id).encode(),
        value=json.dumps({"event": event, "id": str(instance.id)}).encode(),
    )
    _producer.poll(0)   # trigger delivery callbacks without blocking
```

### Management command consumer
Long-running consumer as a Django management command (run via `python manage.py consume_orders`):
```python
# orders/management/commands/consume_orders.py
from confluent_kafka import Consumer, KafkaException
from django.core.management.base import BaseCommand
import json, signal as os_signal

class Command(BaseCommand):
    help = "Consume messages from the orders Kafka topic"

    def handle(self, *args, **options):
        consumer = Consumer({
            "bootstrap.servers": settings.KAFKA_BOOTSTRAP_SERVERS,
            "group.id": "django-orders-consumer",
            "auto.offset.reset": "earliest",
        })
        consumer.subscribe(["orders"])
        running = True

        def shutdown(signum, frame):
            nonlocal running
            running = False

        os_signal.signal(os_signal.SIGTERM, shutdown)

        try:
            while running:
                msg = consumer.poll(timeout=1.0)
                if msg is None:
                    continue
                if msg.error():
                    raise KafkaException(msg.error())
                data = json.loads(msg.value().decode())
                self._handle(data)
        finally:
            consumer.close()

    def _handle(self, data: dict):
        self.stdout.write(f"Processing event: {data}")
        # dispatch to service layer
```

### django-kafka (higher-level)
```python
# settings.py
DJANGO_KAFKA = {"BOOTSTRAP_SERVERS": KAFKA_BOOTSTRAP_SERVERS}

# orders/kafka.py
from django_kafka import kafka
from django_kafka.consumer import Consumer, Topics
from django_kafka.topic import Topic

class OrderTopic(Topic):
    name = "orders"

    def consume(self, record):
        process_order_event(record.value)

@kafka.consumer
class OrderConsumer(Consumer):
    topics = Topics(OrderTopic())
    config = {"group.id": "django-orders"}
```

## Scaffolder Patterns
```
orders/
  signals.py                              # producer via Django signals
  management/commands/consume_orders.py   # management command consumer
  kafka.py                                # django-kafka classes (optional)
  apps.py                                 # register signals in ready()
```

## Dos
- Register signal receivers in `AppConfig.ready()` to avoid double-registration
- Call `_producer.flush()` on application shutdown (connect to `AppConfig` shutdown or `atexit`)
- Use management command consumers and supervise with systemd or Docker entrypoint
- Handle `KafkaException` and log with context before re-raising or continuing

## Don'ts
- Don't create a new `Producer` per signal invocation — use a module-level singleton
- Don't block request handling with `producer.flush()` — use `poll(0)` and flush on shutdown
- Don't commit offsets manually unless you need exactly-once semantics
- Don't run the consumer in a Django view or Celery task — use a dedicated process
