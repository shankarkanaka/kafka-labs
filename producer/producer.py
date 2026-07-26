import os
import time
import json
import random
import logging
from datetime import datetime, timezone
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [PRODUCER] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
log = logging.getLogger(__name__)

# ── Config from environment variables ────────────────────────
BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "localhost:9092")
TOPIC             = os.getenv("TOPIC", "my-topic")
INTERVAL_SEC      = float(os.getenv("INTERVAL_SEC", "2"))   # seconds between messages
MESSAGE_COUNT     = int(os.getenv("MESSAGE_COUNT", "0"))    # 0 = run forever

# ── Sample order data ─────────────────────────────────────────
PRODUCTS  = ["laptop", "phone", "tablet", "monitor", "keyboard", "mouse"]
CUSTOMERS = ["alice", "bob", "charlie", "diana", "eve", "frank"]


def delivery_report(err, msg):
    """Callback fired when a message is delivered or fails."""
    if err:
        log.error(f"Delivery failed for key={msg.key()}: {err}")
    else:
        log.info(
            f"Delivered → topic={msg.topic()} "
            f"partition={msg.partition()} "
            f"offset={msg.offset()} "
            f"key={msg.key().decode()}"
        )


def wait_for_kafka(bootstrap_servers: str, retries: int = 10, delay: int = 5):
    """Wait until Kafka broker is reachable."""
    admin = AdminClient({"bootstrap.servers": bootstrap_servers})
    for attempt in range(1, retries + 1):
        try:
            meta = admin.list_topics(timeout=5)
            log.info(f"Kafka is reachable — {len(meta.topics)} topic(s) found.")
            return
        except Exception as e:
            log.warning(f"Kafka not ready yet (attempt {attempt}/{retries}): {e}")
            time.sleep(delay)
    raise RuntimeError("Could not connect to Kafka after multiple retries.")


def main():
    log.info(f"Bootstrap servers : {BOOTSTRAP_SERVERS}")
    log.info(f"Topic             : {TOPIC}")
    log.info(f"Interval          : {INTERVAL_SEC}s")
    log.info(f"Message count     : {'infinite' if MESSAGE_COUNT == 0 else MESSAGE_COUNT}")

    wait_for_kafka(BOOTSTRAP_SERVERS)

    producer = Producer({
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "acks": "all",                  # wait for all in-sync replicas
        "retries": 3,
    })

    count = 0
    try:
        while MESSAGE_COUNT == 0 or count < MESSAGE_COUNT:
            order_id  = f"order-{random.randint(1000, 9999)}"
            payload   = {
                "order_id":  order_id,
                "customer":  random.choice(CUSTOMERS),
                "product":   random.choice(PRODUCTS),
                "quantity":  random.randint(1, 10),
                "price":     round(random.uniform(9.99, 999.99), 2),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            producer.produce(
                topic=TOPIC,
                key=order_id,
                value=json.dumps(payload),
                callback=delivery_report,
            )
            producer.poll(0)   # trigger delivery callbacks
            count += 1
            time.sleep(INTERVAL_SEC)
    except KeyboardInterrupt:
        log.info("Interrupted — flushing remaining messages...")
    finally:
        producer.flush()
        log.info(f"Done. Total messages sent: {count}")


if __name__ == "__main__":
    main()
