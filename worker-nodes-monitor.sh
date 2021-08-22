#!/bin/bash
sudo su
apt-get update
apt-get -y upgrade
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
sleep 5
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository  -y  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt-get install docker-ce docker-ce-cli containerd.io -y
apt-get update && apt-get install -y apt-transport-https curl

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update

apt-get install -y kubelet kubeadm kubectl

apt-mark hold kubelet kubeadm kubectl
sleep 5

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

sleep 3
sudo kubeadm join :6443 --token kmgobi.pavpxxm3si8iimko --discovery-token-unsafe-skip-ca-verification
