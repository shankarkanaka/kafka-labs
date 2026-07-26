# Kafka Consumer Autoscaling Demo — KEDA

Step-by-step guide to observe Kafka consumer autoscaling using KEDA on a local Kind cluster.

> **Prerequisites:** Kafka cluster running, producer and consumer deployed, KEDA installed.
> See [README.md](README.md) and [KAFKA-APPS.md](KAFKA-APPS.md) before starting this guide.

---

## How KEDA Autoscaling Works

```
Producer sends messages fast
    └── Consumer lag builds up
        └── KEDA detects lag > lagThreshold (5)
            └── Scales consumer pods UP (max 10)
                └── Consumers drain the backlog together
                    └── Lag drops to 0
                        └── KEDA scales consumer pods DOWN (min 1)
```

### Current Configuration

| Setting | Value | File |
|---------|-------|------|
| Producer rate | 1 message per 0.1s (10/sec) | `k8s/producer.yaml` |
| Consumer processing delay | 5s per message (simulated slow) | `k8s/consumer.yaml` |
| KEDA lag threshold | 5 messages | `k8s/keda-scaledobject.yaml` |
| Min consumers | 1 | `k8s/keda-scaledobject.yaml` |
| Max consumers | 10 | `k8s/keda-scaledobject.yaml` |

---

## Setup — Open 4 Terminals Side by Side

Before starting the demo, open 4 PowerShell windows and run one command in each:

**Terminal 1 — Watch pods:**
```powershell
kubectl get pods -n kafka -w
```

**Terminal 2 — Watch ScaledObject (KEDA decisions):**
```powershell
kubectl get scaledobject kafka-consumer-scaler -n kafka -w
```

**Terminal 3 — Producer logs:**
```powershell
kubectl logs -n kafka deployment/kafka-producer -f
```

**Terminal 4 — Consumer logs:**
```powershell
kubectl logs -n kafka deployment/kafka-consumer -f
```

---

## Demo 1: Observe Scale-Up

### Step 1 — Ensure everything is deployed and running

```powershell
kubectl get pods -n kafka
kubectl get scaledobject -n kafka
```

Expected — 1 consumer pod, ScaledObject active:
```
NAME                                    READY   STATUS    
kafka-consumer-xxx                      1/1     Running   
kafka-producer-xxx                      1/1     Running   
```
```
NAME                     SCALETARGETKIND   SCALETARGETNAME   READY   ACTIVE
kafka-consumer-scaler    Deployment        kafka-consumer    True    False
```

### Step 2 — Start the fast producer to build lag

```powershell
kubectl scale deployment/kafka-producer --replicas=1 -n kafka
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=0.1
```

### Step 3 — Watch lag build up in Kafka UI

Open **http://localhost:30080** → **Consumer Groups** → `my-consumer-group`

You will see the lag number increasing rapidly.

### Step 4 — Watch KEDA scale consumers up

Within ~30–60 seconds, KEDA detects lag > 5 and starts scaling:

```
# Terminal 1 — pods scaling up
kafka-consumer-xxx-1    0/1   ContainerCreating
kafka-consumer-xxx-1    1/1   Running
kafka-consumer-xxx-2    0/1   ContainerCreating
kafka-consumer-xxx-2    1/1   Running
...
```

```
# Terminal 2 — ScaledObject becomes ACTIVE
NAME                     READY   ACTIVE   REPLICAS
kafka-consumer-scaler    True    True     3
kafka-consumer-scaler    True    True     5
```

```
# Terminal 4 — Multiple consumers processing in parallel
2026-01-01T10:00:10 [CONSUMER] Received → partition=0 offset=45 key=order-1234
2026-01-01T10:00:10 [CONSUMER] Received → partition=3 offset=38 key=order-5678
```

> 💡 Each consumer pod is assigned different partitions by Kafka's consumer group protocol.
> With 10 partitions and up to 10 consumers, each consumer handles 1 partition at peak scale.

---

## Demo 2: Observe Scale-Down

### Step 1 — Stop the producer (no new messages)

```powershell
kubectl scale deployment/kafka-producer --replicas=0 -n kafka
```

### Step 2 — Watch consumers drain the remaining backlog

In **Terminal 4** you'll see consumers still processing the remaining messages until lag = 0.

In **Kafka UI** → **Consumer Groups** → lag count decreasing to 0.

### Step 3 — Watch KEDA scale consumers back down

Once lag = 0, KEDA scales consumers back to `minReplicaCount` (1):

```
# Terminal 1 — pods terminating
kafka-consumer-xxx-2    1/1   Terminating
kafka-consumer-xxx-3    1/1   Terminating
kafka-consumer-xxx-1    1/1   Terminating
# Only 1 consumer remains
```

```
# Terminal 2 — ScaledObject becomes INACTIVE
NAME                     READY   ACTIVE   REPLICAS
kafka-consumer-scaler    True    False    1
```

### Step 4 — Restart producer

```powershell
kubectl scale deployment/kafka-producer --replicas=1 -n kafka
```

---

## Demo 3: Full Cycle — Scale Up then Down

Run this sequence and watch all 4 terminals:

```powershell
# Phase 1: Build lag — scale UP
kubectl scale deployment/kafka-producer --replicas=1 -n kafka
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=0.1
# Wait 60 seconds — watch consumers scale up...

# Phase 2: Stop producer — scale DOWN
kubectl scale deployment/kafka-producer --replicas=0 -n kafka
# Wait for lag to drain — watch consumers scale down...

# Phase 3: Steady state — normal rate
kubectl scale deployment/kafka-producer --replicas=1 -n kafka
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=2
```

---

## Controlling the Demo

### Speed up producer (build lag faster)

```powershell
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=0.1
```

### Slow down producer (reduce lag)

```powershell
kubectl set env deployment/kafka-producer -n kafka INTERVAL_SEC=2
```

### Stop producer (drain lag → scale down)

```powershell
kubectl scale deployment/kafka-producer --replicas=0 -n kafka
```

### Restart producer

```powershell
kubectl scale deployment/kafka-producer --replicas=1 -n kafka
```

### Manually force consumer replica count (override KEDA temporarily)

```powershell
# Pause KEDA autoscaling
kubectl annotate scaledobject kafka-consumer-scaler -n kafka autoscaling.keda.sh/paused=true

# Scale manually
kubectl scale deployment/kafka-consumer --replicas=3 -n kafka

# Resume KEDA autoscaling
kubectl annotate scaledobject kafka-consumer-scaler -n kafka autoscaling.keda.sh/paused-

```

### Check current consumer lag from CLI

```powershell
kubectl exec -n kafka my-cluster-dual-role-0 -- \
  bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group my-consumer-group \
  --describe
```

Expected output:
```
GROUP              TOPIC      PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
my-consumer-group  my-topic   0          100             145             45
my-consumer-group  my-topic   1          98              143             45
...
```

---

## Tuning the Autoscaler

Edit [`k8s/keda-scaledobject.yaml`](k8s/keda-scaledobject.yaml) and reapply to change behaviour:

| Want to... | Change |
|------------|--------|
| Scale up sooner | Lower `lagThreshold` (e.g. `"2"`) |
| Scale up later | Raise `lagThreshold` (e.g. `"20"`) |
| Allow more consumers | Raise `maxReplicaCount` |
| Scale to zero when idle | Set `minReplicaCount: 0` (also enables `cooldownPeriod`) |

```powershell
# Apply updated ScaledObject
kubectl apply -f k8s/keda-scaledobject.yaml
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| ScaledObject not scaling up | Check `kubectl describe scaledobject kafka-consumer-scaler -n kafka` |
| Consumers not getting messages | Check consumer group: `kubectl logs -n kafka deployment/kafka-consumer` |
| Lag not building | Verify producer is running: `kubectl get pods -n kafka` |
| KEDA pods not running | Check: `kubectl get pods -n keda` |
| ScaledObject shows `READY: False` | KEDA can't reach Kafka — check broker address in ScaledObject |

---

## References

- [KEDA Kafka Scaler docs](https://keda.sh/docs/scalers/apache-kafka/)
- [KEDA ScaledObject spec](https://keda.sh/docs/concepts/scaling-deployments/)
- [Kafka Consumer Groups](https://kafka.apache.org/documentation/#intro_consumers)
- [Kafka Apps guide → KAFKA-APPS.md](KAFKA-APPS.md)
