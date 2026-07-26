# Kafka Producer & Consumer — Python

Python-based Kafka producer and consumer applications, packaged as Docker images and deployable to Kubernetes with KEDA-based autoscaling.

---

## Project Structure

```
producer/
├── producer.py        # Kafka producer — sends order events every N seconds
├── requirements.txt   # confluent-kafka dependency
└── Dockerfile         # Docker image definition

consumer/
├── consumer.py        # Kafka consumer — reads and logs order events
├── requirements.txt   # confluent-kafka dependency
└── Dockerfile         # Docker image definition

k8s/
├── producer.yaml          # Kubernetes Deployment for producer
├── consumer.yaml          # Kubernetes Deployment for consumer
└── keda-scaledobject.yaml # KEDA autoscaler for consumer
```

---

## Prerequisites

- Kind cluster running with Kafka deployed (see [README.md](README.md))
- Podman available on Windows
- KEDA installed on the cluster (see below)

---

## Part 1: Build and Deploy Using the Script (Recommended)

Instead of running steps manually, use the interactive deploy script:

```powershell
.\deploy-apps.bat
```

The script will prompt:
```
Select what to deploy:
  1. Consumer only
  2. Producer only
  3. All (Consumer + Producer + KEDA ScaledObject)

Enter choice [1/2/3]:
```

It handles everything automatically:
- ✅ Checks kubectl context
- ✅ Installs KEDA if not already installed (option 3)
- ✅ Builds the Docker image(s)
- ✅ Loads image(s) into the Kind cluster
- ✅ Deploys Kubernetes manifests
- ✅ Waits for pods to be Running
- ✅ Prints final status and log commands

---

## Part 2: Build Docker Images Manually

If you prefer to run steps individually:

### Build the images

```powershell
# Build producer image
podman build -t kafka-producer:latest ./producer

# Build consumer image
podman build -t kafka-consumer:latest ./consumer
```

### Load images into Kind cluster

```powershell
# Save and load producer image into Kind node
podman save kafka-producer:latest -o kafka-producer.tar
kind load image-archive kafka-producer.tar --name kafka-lab

# Save and load consumer image into Kind node
podman save kafka-consumer:latest -o kafka-consumer.tar
kind load image-archive kafka-consumer.tar --name kafka-lab

# Clean up tar files
Remove-Item kafka-producer.tar, kafka-consumer.tar
```

> 💡 `imagePullPolicy: Never` is set in the Kubernetes manifests so the cluster uses the locally loaded image instead of trying to pull from a registry.
> ⚠️ **Podman prefixes locally built images with `localhost/`** — the manifests use `localhost/kafka-producer:latest` and `localhost/kafka-consumer:latest` to match this.

---

## Part 2: Install KEDA

KEDA (Kubernetes Event-Driven Autoscaling) watches Kafka consumer group lag and scales consumer pods automatically.

```powershell
# Add KEDA Helm repo
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA in its own namespace
helm install keda kedacore/keda --namespace keda --create-namespace
```

Wait for KEDA to be ready:

```powershell
kubectl get pods -n keda -w
```

Expected — all pods Running:
```
NAME                                      READY   STATUS    
keda-operator-*                           2/2     Running
keda-operator-metrics-apiserver-*         1/1     Running
```

> If Helm is not installed: `winget install Helm.Helm`

---

## Part 3: Deploy Producer and Consumer

```powershell
# Deploy producer
kubectl apply -f k8s/producer.yaml

# Deploy consumer
kubectl apply -f k8s/consumer.yaml

# Deploy KEDA ScaledObject (enables autoscaling)
kubectl apply -f k8s/keda-scaledobject.yaml
```

Verify:

```powershell
kubectl get pods -n kafka
kubectl get scaledobject -n kafka
```

---

## Part 4: Watch It in Action

### Watch producer logs (messages being sent)

```powershell
kubectl logs -n kafka deployment/kafka-producer -f
```

Expected output:
```
2026-01-01T10:00:00 [PRODUCER] Bootstrap servers : my-cluster-kafka-bootstrap.kafka.svc:9092
2026-01-01T10:00:00 [PRODUCER] Kafka is reachable — 1 topic(s) found.
2026-01-01T10:00:02 [PRODUCER] Delivered → topic=my-topic partition=3 offset=0 key=order-4821
2026-01-01T10:00:04 [PRODUCER] Delivered → topic=my-topic partition=7 offset=0 key=order-2934
```

### Watch consumer logs (messages being received)

```powershell
kubectl logs -n kafka deployment/kafka-consumer -f
```

Expected output:
```
2026-01-01T10:00:00 [CONSUMER] Subscribed to topic: my-topic
2026-01-01T10:00:02 [CONSUMER] Received  → topic=my-topic partition=3 offset=0 key=order-4821
2026-01-01T10:00:02 [CONSUMER] Order     → id=order-4821 customer=alice product=laptop qty=3 price=$499.99
```

### Watch in Kafka UI

Open **http://localhost:30080** and check:
- **Topics → my-topic** — see messages arriving in real time
- **Consumers → my-consumer-group** — see partition assignments and lag

---

## Part 5: Autoscaling with KEDA

### How it works

```
Producer sends messages fast  →  consumer lag builds up
KEDA detects lag > 10         →  scales consumer pods up
Consumer catches up           →  lag drops to 0
KEDA detects lag = 0          →  scales consumer pods down (after cooldown)
```

### Watch autoscaling in action

Speed up the producer to build lag:

```powershell
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=0.1
```

Watch pods scale up:

```powershell
kubectl get pods -n kafka -w
```

Watch the ScaledObject status:

```powershell
kubectl get scaledobject kafka-consumer-scaler -n kafka -w
```

Slow the producer back down:

```powershell
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=2
```

Watch pods scale back down after the cooldown period (30 seconds).

---

## Configuration Reference

### Producer environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka bootstrap address |
| `TOPIC` | `my-topic` | Topic to produce to |
| `INTERVAL_SEC` | `2` | Seconds between messages |
| `MESSAGE_COUNT` | `0` | Messages to send (0 = forever) |

### Consumer environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BOOTSTRAP_SERVERS` | `localhost:9092` | Kafka bootstrap address |
| `TOPIC` | `my-topic` | Topic to consume from |
| `GROUP_ID` | `my-consumer-group` | Consumer group ID |
| `AUTO_OFFSET_RESET` | `earliest` | Where to start reading (`earliest`/`latest`) |

### KEDA ScaledObject settings ([`k8s/keda-scaledobject.yaml`](k8s/keda-scaledobject.yaml))

| Setting | Value | Description |
|---------|-------|-------------|
| `minReplicaCount` | `1` | Always keep 1 consumer running |
| `maxReplicaCount` | `10` | Scale up to 10 consumers max |
| `lagThreshold` | `10` | Scale up when lag exceeds 10 messages |

> 💡 `pollingInterval` and `cooldownPeriod` are only relevant when `minReplicaCount = 0` (scale to zero). With `minReplicaCount = 1` they have no effect and are omitted to avoid KEDA warnings.

---

## Rebuild and Redeploy After Code Changes

```powershell
# Rebuild images
podman build -t kafka-producer:latest ./producer
podman build -t kafka-consumer:latest ./consumer

# Reload into Kind
podman save kafka-producer:latest -o kafka-producer.tar
kind load image-archive kafka-producer.tar --name kafka-lab
podman save kafka-consumer:latest -o kafka-consumer.tar
kind load image-archive kafka-consumer.tar --name kafka-lab
Remove-Item kafka-producer.tar, kafka-consumer.tar

# Restart deployments to pick up new images
kubectl rollout restart deployment/kafka-producer -n kafka
kubectl rollout restart deployment/kafka-consumer -n kafka
```

---

## References

- [confluent-kafka-python](https://github.com/confluentinc/confluent-kafka-python)
- [KEDA Documentation](https://keda.sh/docs/)
- [KEDA Kafka Scaler](https://keda.sh/docs/scalers/apache-kafka/)
