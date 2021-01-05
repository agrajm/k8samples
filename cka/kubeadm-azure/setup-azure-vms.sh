#!/bin/sh

RG=k8s-kubeadm
LOCATION=australiaeast
SUBNET=$(az network vnet show --name k8s-vnet -g $RG --query subnets[0].id -o tsv)

# Master instance
echo "Creating Kubernetes Master"
az vm create --name kube-master \
   --resource-group $RG \
   --location $LOCATION \
   --image UbuntuLTS \
   --admin-user azureuser \
   --ssh-key-values ~/.ssh/id_rsa_azure.pub \
   --size Standard_DS2_v2 \
   --data-disk-sizes-gb 10 \
   --subnet $SUBNET \
   --public-ip-address-dns-name kube-master-lab

# Nodes intances

az vm availability-set create --name kubeadm-nodes-as --resource-group $RG

for i in 0 1 2; do 
    echo "Creating Kubernetes Node ${i}"
    az vm create --name kube-node-${i} \
       --resource-group $RG \
       --location $LOCATION \
       --availability-set kubeadm-nodes-as \
       --image UbuntuLTS \
       --admin-user azureuser \
       --ssh-key-values ~/.ssh/id_rsa_azure.pub \
       --size Standard_DS2_v2 \
       --data-disk-sizes-gb 10 \
       --subnet $SUBNET \
       --public-ip-address-dns-name kube-node-lab-${i}
done

az vm list --resource-group $RG -d