#!/bin/bash
hostnamectl set-hostname master
# Disable SWAP
sudo sed -i 's/\/swap.img/# \/swap.img/g' /etc/fstab
sudo swapoff -a
sudo rm -rf /swap.img

# Disable Firewall
systemctl stop ufw
systemctl disable ufw

# Create the .conf file to load the modules at bootup and set up required sysctl params
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sleep 2

# Install dependencies
apt-get update -y 
sleep 1
export DEBIAN_FRONTEND=noninteractive
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get install -y libpq-dev apt-transport-https docker-ce-cli
sleep 1

# Install kubeadm,kubectl,kubelet
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
sleep 1 
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sleep 1 
apt-get update
# Set $VERSION to the kubeadm,kubectl,kubelet version
VERSION=1.22.1-00
apt-get install -y kubeadm=$VERSION
echo 'Environment="KUBELET_EXTRA_ARGS=--feature-gates='AllAlpha=false' --container-runtime=remote --cgroup-driver=systemd --container-runtime-endpoint='unix:///var/run/crio/crio.sock' --runtime-request-timeout=5m"' >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo systemctl enable kubelet --now

# Insatll CRI:CRI-O,set $VERSION to the CRI-O version that matches your Kubernetes version
VERSION=1.22
OS=xUbuntu_20.04
cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers-cri-o.gpg add -
sudo apt-get update -y
sudo apt-get install -y cri-o cri-o-runc
sudo systemctl daemon-reload
sudo systemctl enable crio --now
