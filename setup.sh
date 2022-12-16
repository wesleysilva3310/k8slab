#!/bin/bash

# Updating linux
echo "Updating Linux"
sudo apt update -y && sudo apt upgrade -y
echo "Linux updated!"

# Install sshpass
echo "Installing sshpass"
sudo apt-get install sshpass -y
echo "Installation Complete!"

# Instalar o docker
if
        [ "$HOSTNAME" != kmaster ] && [ "$HOSTNAME" != kworker1 ] && [ "$HOSTNAME" != kworker2 ];
then
echo "Installing docker"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt install docker docker.io -y
sudo usermod -aG docker vagrant
echo "Installation Complete!"

# Installing docker-compose
echo "Installing docker compose"
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo curl \
    -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose \
    -o /etc/bash_completion.d/docker-compose
echo "Installation Complete!"
fi

# ssh access without need key pairs. initial login: vagrant vagrant
echo "Configuring ssh access"
sudo su -
sleep 5
file=/etc/ssh/sshd_config
cp -p $file $file.old &&
while read key other
do
 case $key in
 PasswordAuthentication) other=yes;;
 PubkeyAuthentication) other=yes;;
 esac
 echo "$key $other"
done < $file.old > $file
systemctl restart sshd
echo "Configuration complete!"


# Configuring dns server
if [ "$HOSTNAME" = dnsserver ];
then
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo unlink /etc/resolv.conf
echo nameserver 8.8.8.8 | sudo tee /etc/resolv.conf
sudo apt install dnsmasq
sudo systemctl restart dnsmasq
sudo cat >>/etc/hosts<<EOF
192.168.1.100   kmaster
192.168.1.105   dnsserver
192.168.1.101    kworker1
192.168.1.102   kworker2
EOF
fi

#Adding dns server to resolv.conf
sudo cat >>/etc/resolv.conf<<EOF
nameserver 192.168.1.105
EOF

# Installing ansible on kmaster vm
if
        [ "$HOSTNAME" = kmaster ];
then
        echo "Installing ansible on kmaster VM"
        sudo apt install ansible -y
        echo "Installation complete!"
fi

# installing helm on kmaster vm
if
        [ "$HOSTNAME" = kmaster ];
then
        echo "Installing helm on kmaster VM"
        wget https://get.helm.sh/helm-v3.9.0-linux-amd64.tar.gz
        tar -zxvf helm-v3.9.0-linux-amd64.tar.gz
        mv linux-amd64/helm /usr/local/bin/helm
        rm -Rf helm-v3.9.0-linux-amd64.tar.gz linux-amd64
        echo "Installation complete!"
fi

#Kubernetes configuration

if 
        [ "$HOSTNAME" = kmaster ] || [ "$HOSTNAME" = kworker1 ] || [ "$HOSTNAME" = kworker2 ];
then
echo "[k8s TASK 1] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

echo "[k8s TASK 2] Stop and Disable firewall"
systemctl disable --now ufw >/dev/null 2>&1

echo "[k8s TASK 3] Enable and Load Kernel modules"
cat >>/etc/modules-load.d/containerd.conf<<END1
overlay
br_netfilter
END1
modprobe overlay
modprobe br_netfilter

echo "[k8s TASK 4] Add Kernel settings"
cat >>/etc/sysctl.d/kubernetes.conf<<END2
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
END2
sysctl --system >/dev/null 2>&1

echo "[k8s TASK 5] Install containerd runtime"
apt update -qq >/dev/null 2>&1
apt install -qq -y containerd apt-transport-https >/dev/null 2>&1
mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

echo "[k8s TASK 6] Add apt repo for kubernetes"
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - >/dev/null 2>&1
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main" >/dev/null 2>&1

echo "[k8s TASK 7] Install Kubernetes components (kubeadm, kubelet and kubectl)"
apt install -qq -y kubeadm=1.22.0-00 kubelet=1.22.0-00 kubectl=1.22.0-00 >/dev/null 2>&1

echo "[k8s TASK 8] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd

echo "[k8s TASK 9] Set root password"
echo -e "kubeadmin\nkubeadmin" | passwd root >/dev/null 2>&1
echo "export TERM=xterm" >> /etc/bash.bashrc

echo "[k8s TASK 10] Update /etc/hosts file"
cat >>/etc/hosts<<END3
192.168.1.100  kmaster
192.168.1.101   kworker1
192.168.1.102  kworker2
END3

echo "K8s bootstrap configuration complete!"
fi
#Creating script to add kube dir and permissions
if
        [ "$HOSTNAME" = kmaster ];
then
echo "[k8s kmaster TASK 1] Pull required containers"
kubeadm config images pull >/dev/null 2>&1

echo "[k8s kmaster TASK 2] Initialize Kubernetes Cluster"
kubeadm init --apiserver-advertise-address=192.168.1.100 --pod-network-cidr=192.168.0.0/16 >> /root/kubeinit.log 2>/dev/null

echo "[k8s kmaster TASK 3] Deploy Calico network"
kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml >/dev/null 2>&1

echo "[k8s kmaster TASK 4] Generate and save cluster join command to /joincluster.sh"
kubeadm token create --print-join-command > /joincluster.sh 2>/dev/null
sleep 30

#run ping on workers before integrate them!

cat > kubemastersetup.sh << END4
#run as vagrant user
echo "Creating kube dir and permissions"
 mkdir -p $HOME/.kube
 sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
 sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "k8s kmaster configuration complete!"
END4
fi

#Creating script to k8s workers to be added to cluster
if 
        [ "$HOSTNAME" = kworker1 ] || [ "$HOSTNAME" = kworker2 ];
then
#run this only when creating the VM for the first time, using root user
cat > /usr/joincluster.sh << EOF
echo "Join node to Kubernetes Cluster"
apt install -qq -y sshpass >/dev/null 2>&1
sshpass -p "kubeadmin" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no kmaster:/joincluster.sh /joincluster.sh 2>/dev/null
bash /joincluster.sh >/dev/null 2>&1
EOF
fi

# Install docker on k8s nodes
if
        [ "$HOSTNAME" = kmaster ];
then
echo "Installing docker"
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt install docker docker.io -y
sudo usermod -aG docker vagrant
echo "Installation Complete!"

# Installing docker-compose
echo "Installing docker compose"
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo curl \
    -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose \
    -o /etc/bash_completion.d/docker-compose
echo "Installation Complete!"
fi