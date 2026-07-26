# Kafka Labs — Strimzi on Kubernetes

Step-by-step guide to deploy Apache Kafka on Kubernetes using the [Strimzi Operator](https://strimzi.io/), with Kafka UI and topic management via CRDs.

## Prerequisites

- Kubernetes cluster (Docker Desktop, Kind, Minikube, etc.)
- `kubectl` configured and connected to your cluster
- A default StorageClass for persistent volumes (e.g. `standard`)

## Project Files

| File | Purpose |
|------|---------|
| `strimzi.txt` | Strimzi operator install output (reference) |
| `kafka-namespace.yaml` | Kafka namespace definition |
| `kafka.yaml` | Single-node Kafka cluster (KRaft, 10Gi storage) |
| `kafka-ui.yaml` | Kafka UI web interface |
| `kafka-topic.yaml` | Example topic with 10 partitions |

---

## Step 1: Create Namespace and Install Strimzi Operator

Create the `kafka` namespace using the resource file:

```bash
kubectl apply -f kafka-namespace.yaml
```

Verify:

```bash
kubectl get namespace kafka
```

Install the Strimzi Cluster Operator using the official manifest:

```bash
kubectl create -f https://strimzi.io/install/latest?namespace=kafka -n kafka
```

Expected output (saved in `strimzi.txt`):

```
configmap/strimzi-cluster-operator created
clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-namespaced created
customresourcedefinition.apiextensions.k8s.io/kafkaconnectors.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkas.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkatopics.kafka.strimzi.io created
clusterrole.rbac.authorization.k8s.io/strimzi-kafka-broker created
clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-global created
rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-entity-operator-delegation created
customresourcedefinition.apiextensions.k8s.io/kafkausers.kafka.strimzi.io created
rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-leader-election created
clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-kafka-broker-delegation created
serviceaccount/strimzi-cluster-operator created
clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-watched created
clusterrole.rbac.authorization.k8s.io/strimzi-cluster-operator-leader-election created
customresourcedefinition.apiextensions.k8s.io/kafkamirrormaker2s.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkarebalances.kafka.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkanodepools.kafka.strimzi.io created
clusterrole.rbac.authorization.k8s.io/strimzi-entity-operator created
clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator created
rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-watched created
customresourcedefinition.apiextensions.k8s.io/strimzipodsets.core.strimzi.io created
customresourcedefinition.apiextensions.k8s.io/kafkaconnects.kafka.strimzi.io created
rolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator created
deployment.apps/strimzi-cluster-operator created
clusterrole.rbac.authorization.k8s.io/strimzi-kafka-client created
clusterrolebinding.rbac.authorization.k8s.io/strimzi-cluster-operator-kafka-client-delegation created
customresourcedefinition.apiextensions.k8s.io/kafkabridges.kafka.strimzi.io created
```

Verify the operator is running:

```bash
kubectl get pods -n kafka
kubectl get deployment strimzi-cluster-operator -n kafka
```

You should see the operator pod in `Running` state.

Verify CRDs are installed:

```bash
kubectl get crd | grep kafka.strimzi.io
```

---

## Step 2: Deploy Kafka Cluster

This project uses a **single-node KRaft cluster** (based on `strimzi/examples/kafka/kafka-single-node.yaml`) with:

- 1 node (combined broker + controller roles)
- Kafka version **4.3.0**
- 10Gi persistent storage
- Plain listener on port **9092** and TLS listener on port **9093**
- Topic Operator and User Operator enabled

Apply the cluster manifest:

```bash
kubectl apply -f kafka.yaml
```

Monitor rollout:

```bash
kubectl get kafka,kafkanodepool -n kafka
kubectl get pods -n kafka -w
```

Wait until the Kafka resource shows `READY True`:

```bash
kubectl get kafka my-cluster -n kafka
```

Expected resources created:

| Resource | Name |
|----------|------|
| Kafka CR | `my-cluster` |
| KafkaNodePool | `dual-role` |
| Kafka pod | `my-cluster-dual-role-0` |
| Entity Operator | `my-cluster-entity-operator-*` |
| Bootstrap service | `my-cluster-kafka-bootstrap` |
| PVC | `data-0-my-cluster-dual-role-0` (10Gi) |

Kafka bootstrap address (inside the cluster):

```
my-cluster-kafka-bootstrap.kafka.svc:9092   # plain
my-cluster-kafka-bootstrap.kafka.svc:9093   # TLS
```

---

## Step 3: Deploy Kafka UI

Deploy the web UI to browse topics, messages, and consumer groups:

```bash
kubectl apply -f kafka-ui.yaml
```

Verify:

```bash
kubectl get pods,svc -n kafka -l app=kafka-ui
```

### Access Kafka UI

The service uses `NodePort` type, accessible directly at:

```
http://localhost:30080
```

No `port-forward` needed — Kind maps the node port directly to `localhost`.

**Port-forward (fallback, works on any cluster):**

```bash
kubectl port-forward svc/kafka-ui 8080:8080 -n kafka
```

Then open: http://localhost:8080

---

## Step 4: Create a Kafka Topic (Strimzi CRD)

The recommended way to create topics with Strimzi is the **`KafkaTopic` custom resource**, managed by the Topic Operator.

Apply the example topic (10 partitions, replication factor 1):

```bash
kubectl apply -f kafka-topic.yaml
```

Verify:

```bash
kubectl get kafkatopic -n kafka
kubectl describe kafkatopic my-topic -n kafka
```

Expected output:

```
NAME       CLUSTER      PARTITIONS   REPLICATION FACTOR   READY
my-topic   my-cluster   10           1                    True
```

The topic should also appear in Kafka UI under **Topics**.

### Create additional topics

Copy `kafka-topic.yaml`, change the metadata name and spec, and apply:

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: orders
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster   # must match Kafka cluster name
spec:
  partitions: 10
  replicas: 1                       # max 1 on single-node cluster
```

---

## Useful Commands

Check all Kafka resources:

```bash
kubectl get kafka,kafkanodepool,kafkatopic,pods,svc,pvc -n kafka
```

Check operator logs:

```bash
kubectl logs -n kafka deployment/strimzi-cluster-operator --tail=50
```

Produce/consume test messages (from inside the Kafka pod):

```bash
# Produce
kubectl exec -n kafka my-cluster-dual-role-0 -it -- \
  bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic my-topic

# Consume
kubectl exec -n kafka my-cluster-dual-role-0 -it -- \
  bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic my-topic --from-beginning
```

List topics via CLI:

```bash
kubectl exec -n kafka my-cluster-dual-role-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

---

## Cleanup

Remove resources in reverse order:

```bash
kubectl delete -f kafka-topic.yaml
kubectl delete -f kafka-ui.yaml
kubectl delete -f kafka.yaml
```

To uninstall the Strimzi operator:

```bash
kubectl delete -f https://strimzi.io/install/latest?namespace=kafka -n kafka
```

---

## References

- [Strimzi Documentation](https://strimzi.io/docs/operators/latest/overview.html)
- [Strimzi Quick Start](https://strimzi.io/quickstarts/)
- [Strimzi Examples](strimzi/examples/)
- [Kafka UI (Kafbat)](https://github.com/kafbat/kafka-ui)
