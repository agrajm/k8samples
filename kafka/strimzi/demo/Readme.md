## Setup 

-- In kafka/strimzi/demo dir ---

```
kubectl create ns kafka
k config set-context --current --namespace=kafka
```

```
k apply -f strimzi-cluster-operator-0.14.0.yaml
```

-- Verify CRD, Deployment etc --

```
kubectl apply -f single-persistent.yaml 
```

-- Verify Pods, Services, kafkas, zookeeper etc, describe kafka cluster -- 

-- Run Simple producer and consumers to talk to Kafka using ClusterIP svc --

```
kubectl -n kafka run kafka-producer -ti --image=strimzi/kafka:0.14.0-kafka-2.3.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --broker-list my-cluster-kafka-bootstrap:9092 --topic my-topic
```

```
kubectl -n kafka run kafka-consumer -ti --image=strimzi/kafka:0.14.0-kafka-2.3.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning
```

```
kubectl -n kafka run kafka-consumer2 -ti --image=strimzi/kafka:0.14.0-kafka-2.3.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning
```

### Bonus

-- Check Containers in a Pod ---

```
k get pod my-cluster-kafka-0 -o jsonpath='{.spec.containers[*].name}'
k get pod my-cluster-zookeeper-0 -o jsonpath='{.spec.containers[*].name}'
```

tls-sidecar -- exec into it or see logs