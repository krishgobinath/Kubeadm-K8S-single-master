#!/bin/bash
PROJECT="charlie-dev"
PROJECT_IMAGE_NAME="ubuntu-os-cloud"
PROJECT_IMAGE_FAMILY="ubuntu-2104"
ZONE="us-central1-c"
WORKER_ZONE_EAST="us-east1-b"
WORKER_ZONE_WEST="us-west1-a"
WORKER_ZONE_CENTRAL="us-central1-c"
MASTER_MACHINE_TYPE="n1-standard-32"
MONITOR_MACHINE_TYPE="n1-highmem-32"
WORKER_MACHINE_TYPE="n1-standard-2"
K8S_MAX_WORKER_NODES=3
MONITORING_VM="cs-monitor"
MASTER_1="cs-master-1"
TOKEN_KEY="kmgobi.pavpxxm3si8iimko"
CERTIFICATE_KEY="1d1b2b6dc0ba56877b882dcfb02bee8e60ba56b84cd485c61375dd21f651cb94"
WORKER_NODE_TEMPLATE="worker-node-template"
WORKER_NODE_GROUP="worker-node-group"
WORKER_NODE_DISK_SIZE="50GB"

function log {
  echo "`date +'%b %d %T.000'`: INFO: $@"
}

function rexec() {
  local vm_name=$1
  local cmd=$2
  log "Running remote cmd " $cmd " on instance " $vm_name
  gcloud compute ssh ${vm_name} --project $PROJECT --zone $ZONE --command="$cmd"
}


function deploy_master {
  local vm_name=${MASTER_1}
  log "Deploying master ${vm_name}"
  gcloud compute instances create $vm_name --project=$PROJECT --image-project $PROJECT_IMAGE_NAME --image-family $PROJECT_IMAGE_FAMILY --zone=$ZONE --machine-type $MASTER_MACHINE_TYPE --boot-disk-type=pd-standard --boot-disk-size=50GB --metadata-from-file=startup-script=./master-node.sh --scopes=compute-rw
  sleep 10
}

function deploy_monitor {
  local vm_name="cs-monitor-1"
  log "Deploying Monitor Node ${vm_name}"
  echo $(cp worker-node.sh worker-nodes-monitor.sh)
  master_ip=$(gcloud compute instances list --project $PROJECT --filter=${vm_name} --format "get(networkInterfaces[0].networkIP)")
  local kadm_join="sudo kubeadm join ${master_ip}:6443 --token ${TOKEN_KEY} --discovery-token-unsafe-skip-ca-verification"
  echo ${kadm_join} | tee -a worker-nodes-monitor.sh
  gcloud compute instances create $vm_name --project=$PROJECT --image-project $PROJECT_IMAGE_NAME --image-family $PROJECT_IMAGE_FAMILY --zone=$ZONE --machine-type $MONITOR_MACHINE_TYPE --boot-disk-type=pd-standard --boot-disk-size=500GB --metadata-from-file=startup-script=./worker-nodes-modified.sh --scopes=compute-rw
}

function master_init {
  local vm_name=${MASTER_1}
  local master_ip=$(gcloud compute instances list --project $PROJECT --filter=${vm_name} --format "get(networkInterfaces[0].networkIP)")
  local extmaster_ip=$(gcloud compute instances list --project $PROJECT --filter=${vm_name} --format "get(networkInterfaces[0].accessConfigs[0].natIP)")
  local kadm_init="sudo kubeadm init --upload-certs --pod-network-cidr=192.0.0.0/8 --token ${TOKEN_KEY} --certificate-key ${CERTIFICATE_KEY} --apiserver-cert-extra-sans ${master_ip},${extmaster_ip}"
  echo ${MASTER_1} "${kadm_init}"
  rexec ${MASTER_1} "${kadm_init}"
  sleep 240
  rexec ${MASTER_1} "mkdir -p ~/.kube"
  rexec ${MASTER_1} "sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config"
  rexec ${MASTER_1} "sudo cp -i /etc/kubernetes/admin.conf ~/admin.conf"
  rexec ${MASTER_1} "sudo chmod 777 ~/.kube/config"
  rexec ${MASTER_1} "sudo cp -i ~/.kube/config ~/admin.conf"
#  rexec ${MASTER_1} "sed 's/10.128.0.22/35.188.147.152/' ~/admin.conf > k8s-admin.conf"
}


function deploy_worker_nodes_group {
  
  echo $(cp worker-node.sh worker-nodes-modified.sh)
  master_ip=$(gcloud compute instances list --project $PROJECT --filter=${MASTER_1} --format "get(networkInterfaces[0].networkIP)")
  local kadm_join="sudo kubeadm join ${master_ip}:6443 --token ${TOKEN_KEY} --discovery-token-unsafe-skip-ca-verification"
  echo ${kadm_join} | tee -a worker-nodes-modified.sh

  gcloud compute  instance-templates create ${WORKER_NODE_TEMPLATE} \
    --project=$PROJECT --image-project $PROJECT_IMAGE_NAME \
    --image-family $PROJECT_IMAGE_FAMILY \
    --machine-type $WORKER_MACHINE_TYPE --boot-disk-type=pd-standard \
    --boot-disk-size=$WORKER_NODE_DISK_SIZE --scopes=compute-rw \
    --metadata-from-file=startup-script=./worker-nodes-modified.sh

  gcloud compute instance-groups managed create ${WORKER_NODE_GROUP} \
    --template ${WORKER_NODE_TEMPLATE} --size ${K8S_MAX_WORKER_NODES} \
    --zone=${WORKER_ZONE_CENTRAL} --project=$PROJECT
}

function install_cilium {
  rexec ${MASTER_1} "helm repo add cilium https://helm.cilium.io/"
  local master_ip=$(gcloud compute instances list --project $PROJECT --filter=${MASTER_1} --format "get(networkInterfaces[0].networkIP)")
  local helm_cmd="helm install cilium cilium/cilium --version 1.9.4 --namespace kube-system --set endpointHealthChecking.enabled=false --set healthChecking=false --set ipam.mode=kubernetes --set k8sServiceHost=${master_ip} --set k8sServicePort=6443 --set prometheus.enabled=true --set operator.prometheus.enabled=true"
  rexec ${MASTER_1} "${helm_cmd}"
}

function install_prometheus {
  gcloud compute scp ./prom.yaml --project $PROJECT --zone $ZONE $MASTER_1:~/monitor.yaml
  rexec ${MASTER_1} "kubectl apply -f ~/monitor.yaml"
  rexec ${MASTER_1} "${helm_cmd}"
}

#deploy_master
#sleep 300
#master_init
#sleep 5
#deploy_monitor
sleep 5
deploy_worker_nodes_group
#sleep 120
#install_cilium
#install_prometheus
