# TLS Demo

```
helm install strimzi/strimzi-kafka-operator --namespace tls-kafka --name kafka-operator-tls
```

```
k apply -f tls-kafka.yaml
k apply -f kafka-topics.yaml 
k apply -f kafka-users.yaml
k apply -f kafka-client.yaml 
```

Install the Certificates in the KeyStore
do for all clients
```
k cp ./setup_ssl.sh kafkaclient-1:/opt/kafka/setup_ssl.sh
k exec -it kafkaclient-1 -- bash setup_ssl.sh
```

Performance Test
```
kubectl exec -n kafka -it kafkaclient-0 -- bin/kafka-producer-perf-test.sh --topic test --num-records 50000000 --record-size 100 --throughput -1 --producer-props acks=1 bootstrap.servers=my-tls-cluster-kafka-brokers.tls-kafka:9093 buffer.memory=67108864 batch.size=8196
```