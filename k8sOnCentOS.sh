#!/bin/env bash
#
/**
 * @Description： k8s 集群部署,非HA
 * @Author: chenqi
 * @Date: 2020-12-30
 * @System: CentOS
 */

install_runtime(){
	# runtime is Docker
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum -y install docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo systemctl status docker.service
}

install_kubeadm(){
	cat <<EOF > /etc/yum.repos.d/kubernetes.repo
	[kubernetes]
	name=Kubernetes
	# baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
	baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
	enabled=1
	# gpgcheck=1
	# repo_gpgcheck=1
	gpgcheck=0
	repo_gpgcheck=0
	# gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
	gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
	EOF

	# 将 SELinux 设置为 permissive 模式（相当于将其禁用）
	setenforce 0
	sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
	# # 禁止swap
	# sysctl vm.swappiness=1
	# echo 'vm.swappiness=1' >> /etc/sysctl.conf

	# 无法正确路由的问题可能情况
	cat <<EOF >  /etc/sysctl.d/k8s.conf
	net.bridge.bridge-nf-call-ip6tables = 1
	net.bridge.bridge-nf-call-iptables = 1
	EOF
	sysctl --system

	yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

	systemctl enable --now kubelet
	systemctl daemon-reload
	systemctl restart kubelet
	systemctl status kubelet.service
}

kubeadm_init(){
	kubeadm init --pod-network-cidr=10.244.0.0/16 > kubeadm_init.txt
	# master 节点有多块网卡，可以通过参数 apiserver-advertise-address 来指定你想要暴露的服务地址
	# kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.131.128 > kubeadm_init.txt
}

kubeadm_join(){
	cat kubeadm_init.txt
	KUBEADM_JOIN=`tail -1 kubeadm_init.txt`
	echo $KUBEADM_JOIN
}


copy_kubeconfig(){
	if [[ $EUID -ne 0 ]];then
		export KUBECONFIG=/etc/kubernetes/admin.conf
	else
		mkdir -p $HOME/.kube
		sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
		sudo chown $(id -u):$(id -g) $HOME/.kube/config
	fi

	# 为了使用更便捷，启用 kubectl 命令的自动补全功能
	echo "source <(kubectl completion bash)" >> ~/.bashrc
}

install_add_on(){
	# install CNI插件 pod网格
	kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
	# install Dashboard 
	
	systemctl restart kubelet

	kubectl get pods --all-namespaces
}

if [[ $HOSTNAME -ne master ]]; then
	#statements
	install_runtime
	install_kubeadm
	kubeadm_init
	copy_kubeconfig
	install_add_on
else
	install_runtime
	install_kubeadm
fi