#!/bin/sh

echo 'Master VM is being created'

multipass launch -c 2 -m 2G -d 20G -n master

echo 'Master VM is sucessfully created'

echo 'Node1 VM is being created'

multipass launch -c 2 -m 2G -d 20G -n node1

echo 'Node1 VM is sucessfully created'

echo 'Node2 VM is being created'

multipass launch -c 2 -m 2G -d 20G -n node2

echo 'Node2 VM is sucessfully created'

masterIP=`multipass exec master -- hostname -I`
node1IP=`multipass exec node1 -- hostname -I`
node2IP=`multipass exec node2 -- hostname -I`
echo $masterIP
echo $node1IP
echo $node2IP

for Item in master node1 node2
do
    echo "${Item}"
    multipass exec ${Item} -- bash <<EOF
    sudo hostnamectl set-hostname "${Item}.k.net"
    echo "${masterIP}  master.k.net    master" | sudo tee -a /etc/hosts
    echo "${node1IP}  node1.k.net    node1" | sudo tee -a /etc/hosts
    echo "${node2IP}  node2.k.net    node2" | sudo tee -a /etc/hosts
    echo "FLANNEL_NETWORK=10.96.0.0/12" | sudo tee -a /run/flannel/subnet.env
    echo "FLANNEL_SUBNET=10.96.0.1/24" | sudo tee -a /run/flannel/subnet.env
    echo "FLANNEL_MTU=1450" | sudo tee -a /run/flannel/subnet.env
    echo "FLANNEL_IPMASQ=true" | sudo tee -a /run/flannel/subnet.env
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo tee /etc/modules-load.d/containerd.conf <<INTERNAL
    overlay
    br_netfilter
INTERNAL
    sudo modprobe overlay
    sudo modprobe br_netfilter
    sudo tee /etc/sysctl.d/kubernetes.conf <<INTERNAL1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.bridge.bridge-nf-call-iptables = 1
    net.ipv4.ip_forward = 1
INTERNAL1
    sudo sysctl --system
    sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install -y containerd.io
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
   
EOF
done



 multipass exec master -- bash <<EOF
    sudo kubeadm init --control-plane-endpoint=master.k.net
    mkdir -p /home/ubuntu/.kube
    sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    sudo chown $(id -u):$(id -g) /home/ubuntu/.kube/config
EOF

addNodeCmd=`multipass exec master -- kubeadm token create --print-join-command`
echo $addNodeCmd

 multipass exec node1 -- bash <<EOF
   sudo $addNodeCmd
EOF

 multipass exec node2 -- bash <<EOF
    sudo $addNodeCmd
EOF

 multipass exec master -- bash <<EOF
    kubectl apply -f kube-flannel.yml
EOF




    
