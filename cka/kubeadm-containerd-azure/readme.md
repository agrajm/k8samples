# Using Kubeadm with Azure

### Resource Group & Basic Infra - VNet, Custom Image
```
az group create --name kubeadm --location australiaeast
```
### Base Image VM 
```
az vm create \
  --resource-group kubeadm \
  --name base-vm \
  --image UbuntuLTS \
  --size Standard_B2s \
  --admin-username azureuser \
  --tags name=base-vm \
  --ssh-key-value ~/.ssh/id_azureuser.pub
```

### SSH TO VM using Public IP and install required software

#### Prepare the Env
```
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay br_netfilter
```

#### Setup required sysctl params, these persist across reboots.
```
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"

apt-get update && apt-get install -y containerd.io

mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml

# since UbuntuLTS uses systemd as the init system
sed -i 's/systemd_cgroup = false/systemd_cgroup = true/' /etc/containerd/config.toml
```

#### Installing kubeadm to base-vm
```
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update && apt-get install -y kubelet kubeadm kubectl && apt-mark hold kubelet kubeadm kubectl

# since containerd is configured to use the systemd cgroup driver
echo 'KUBELET_EXTRA_ARGS=--cgroup-driver=systemd' > /etc/default/kubelet
```

### Deprovision user & exit VM

##### Create Image
```
az vm deallocate \
   --resource-group kubeadm \
   --name base-vm

az vm generalize \
   --resource-group kubeadm \
   --name base-vm

az image create \
   --resource-group kubeadm \
   --name kubeadm-base-image --source base-vm

# Delete the base vm once the image is created

az vm delete \
   --resource-group kubeadm \
   --name base-vm

az resource delete --ids $(az resource list --tag name=base-vm --query "[].id" -otsv)
```

## Create VNET and VMs for hosting k8s cluster

```
RG=kubeadm
LOCATION=australiaeast

az group create --name $RG --location $LOCATION

az network vnet create --name k8s-vnet --resource-group $RG --location $LOCATION --address-prefixes 172.10.0.0/16 --subnet-name k8s-subnet1 --subnet-prefixes 172.10.1.0/24

SUBNET_ID=$(az network vnet show --name k8s-vnet -g $RG --query subnets[0].id -o tsv)
```
### Bastion
```
az network vnet subnet create -g $RG --vnet-name k8s-vnet -n AzureBastionSubnet \
    --address-prefixes 172.10.2.0/24

az network public-ip create --resource-group $RG --name MyBastionPIP --sku Standard --location $LOCATION

az network bastion create --location $LOCATION --name MyBastionHost --public-ip-address MyBastionPIP --resource-group $RG --vnet-name k8s-vnet
```

### Master instance - No PIP
```
echo "Creating Kubernetes Master"
az vm create --name kube-master \
   --resource-group $RG \
   --location $LOCATION \
   --image kubeadm-base-image \
   --admin-user azureuser \
   --ssh-key-values ~/.ssh/id_azureuser.pub \
   --size Standard_DS2_v2 \
   --data-disk-sizes-gb 10 \
   --subnet $SUBNET_ID \
   --public-ip-address ""
```
### Nodes intances
```
az vm availability-set create --name kubeadm-nodes-as --resource-group $RG

for i in 0 1 2; do 
    echo "Creating Kubernetes Node ${i}"
    az vm create --name kube-node-${i} \
       --resource-group $RG \
       --location $LOCATION \
       --availability-set kubeadm-nodes-as \
       --image kubeadm-base-image \
       --admin-user azureuser \
       --ssh-key-values ~/.ssh/id_azureuser.pub \
       --size Standard_DS2_v2 \
       --data-disk-sizes-gb 10 \
       --subnet $SUBNET_ID \
       --public-ip-address ""
done

az vm list --resource-group $RG -d

```

## Use kubeadm to create cluster 

### SSH to Master node

```
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

gives something like 

[init] Using Kubernetes version: v1.21.2
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kube-master kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 172.10.1.4]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [kube-master localhost] and IPs [172.10.1.4 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [kube-master localhost] and IPs [172.10.1.4 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[apiclient] All control plane components are healthy after 25.501577 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config-1.21" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node kube-master as control-plane by adding the labels: [node-role.kubernetes.io/master(deprecated) node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node kube-master as control-plane by adding the taints [node-role.kubernetes.io/master:NoSchedule]
[bootstrap-token] Using token: t3fequ.cmu59t4lfw8j8p3u
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 172.10.1.4:6443 --token t3fequ.cmu59t4lfw8j8p3u \
        --discovery-token-ca-cert-hash sha256:9f773c118ffac84de197e635e3c2c8853ab9171f81ef51aad7e76b2311f0c4b3
```

### Configure kubectl 
As per the instructions in the output of kubeadm init
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Install Pod Network Add On - We are using Calico

For calico (from their quickstart)

```
kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
```
For calico custom operators change the pod network id as used above in kubeadm init command 
```
kubectl create -f calico-custom-resources.yaml
```

### Now the master node is ready 

```
kubectl get nodes -o wide
```

## Worker Nodes 
### Use the kubeadm join on each worker node

```
kubeadm join 172.10.1.4:6443 --token t3fequ.cmu59t4lfw8j8p3u \
        --discovery-token-ca-cert-hash sha256:9f773c118ffac84de197e635e3c2c8853ab9171f81ef51aad7e76b2311f0c4b3
```
If this fails in pre-flight checks - can be due to https://github.com/containerd/containerd/issues/4581
So do the following first
```
sudo rm /etc/containerd/config.toml
sudo systemctl restart containerd
```
Now again do kubeadm join 

Do this on each worker node. You might have to point to the kubeconfig at /etc/kuberenetes/kubelet.conf for kubectl to work

### Congratulations & that's it. Your worker nodes are ready - you we can deploy workloads 
