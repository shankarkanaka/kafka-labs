import os
import json
import signal
import logging
from confluent_kafka import Consumer, KafkaError, KafkaException

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [CONSUMER] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S"
)
log = logging.getLogger(__name__)

# ── Config from environment variables ────────────────────────
BOOTSTRAP_SERVERS    = os.getenv("BOOTSTRAP_SERVERS", "localhost:9092")
TOPIC                = os.getenv("TOPIC", "my-topic")
GROUP_ID             = os.getenv("GROUP_ID", "my-consumer-group")
AUTO_OFFSET_RESET    = os.getenv("AUTO_OFFSET_RESET", "earliest")
PROCESSING_DELAY_SEC = float(os.getenv("PROCESSING_DELAY_SEC", "0"))  # 0 = no delay

# ── Graceful shutdown ─────────────────────────────────────────
running = True

def shutdown_handler(signum, frame):
    global running
    log.info("Shutdown signal received — stopping consumer...")
    running = False

signal.signal(signal.SIGTERM, shutdown_handler)
signal.signal(signal.SIGINT,  shutdown_handler)


def process_message(msg):
    """Process a single Kafka message."""
    try:
        payload = json.loads(msg.value().decode("utf-8"))
        log.info(
            f"Received  → topic={msg.topic()} "
            f"partition={msg.partition()} "
            f"offset={msg.offset()} "
            f"key={msg.key().decode() if msg.key() else 'None'}"
        )
        log.info(
            f"Order     → id={payload.get('order_id')} "
            f"customer={payload.get('customer')} "
            f"product={payload.get('product')} "
            f"qty={payload.get('quantity')} "
            f"price=${payload.get('price')}"
        )
    except json.JSONDecodeError:
        log.warning(f"Non-JSON message: {msg.value()}")


def main():
    log.info(f"Bootstrap servers : {BOOTSTRAP_SERVERS}")
    log.info(f"Topic             : {TOPIC}")
    log.info(f"Consumer group    : {GROUP_ID}")
    log.info(f"Auto offset reset : {AUTO_OFFSET_RESET}")

    consumer = Consumer({
        "bootstrap.servers":  BOOTSTRAP_SERVERS,
        "group.id":           GROUP_ID,
        "auto.offset.reset":  AUTO_OFFSET_RESET,
        "enable.auto.commit": True,
        "auto.commit.interval.ms": 5000,
        "session.timeout.ms": 30000,
        "heartbeat.interval.ms": 10000,
    })

    consumer.subscribe([TOPIC])
    log.info(f"Subscribed to topic: {TOPIC}")

    processed = 0
    try:
        while running:
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                continue   # no message within timeout — keep polling

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    # End of partition — not an error, just caught up
                    log.debug(
                        f"End of partition: {msg.topic()} "
                        f"[{msg.partition()}] at offset {msg.offset()}"
                    )
                else:
                    raise KafkaException(msg.error())
                continue

            process_message(msg)
            processed += 1

    except KafkaException as e:
        log.error(f"Kafka error: {e}")
    finally:
        log.info(f"Closing consumer. Total messages processed: {processed}")
        consumer.close()


if __name__ == "__main__":
    main()
