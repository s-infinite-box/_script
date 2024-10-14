#!/bin/bash
# 失败阻断
#set -e
# 打印脚本执行过程
set -x
# 预执行  可能会导致报错 /root/.bashrc: line 6: PS1: unbound variable
# set -u

if [[ -z $cri_socket ]]; then
  echo "no set cri_socket, exit"
  exit
fi


printf "\n###pull images for kubernetes control plan component\n"
if ! [[ $kube_version == 'last' ]]; then
  kube_version_str_images="--kubernetes-version=$kube_version"
fi

# 判断kubelet是否启动 如果二进制获取的kubelet 需要手动启动kubelet
kubelet_svc_file_path='/lib/systemd/system/kubelet.service'
if  [ -z "$(pgrep kubelet)" ]
then
  cat > $kubelet_svc_file_path <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable kubelet
fi

kubeadm_pull_images_cmd="kubeadm config images pull $cri_socket $kube_version_str_images --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers"

executing_command "$kubeadm_pull_images_cmd"

if ! [ -e /sys/fs/cgroup/systemd ]; then
    echo "/sys/fs/cgroup/systemd not exist, assign cgroup is systemd"
    sudo mkdir /sys/fs/cgroup/systemd
    sudo mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd
fi

kubeadm_init_str="kubeadm init \
--image-repository registry.cn-hangzhou.aliyuncs.com/google_containers \
--service-cidr=$SERVICE_CIDR \
--pod-network-cidr=10.244.0.0/16 \
--apiserver-advertise-address=$master_ip \
$cri_socket \
$kube_version_str_images  \
--upload-certs"
#--apiserver-cert-extra-sans=127.0.0.1,ub99 \
printf "\n###init control plan\n%s\n" "$kubeadm_init_str"
if ! eval "$kubeadm_init_str"; then
  printf "init control plan error, exit\n"
  exit
fi

printf "\n###add kubeconfig to ~/kube/config, set kubeadm, kubectl and crictl completion\n"
#for f in `ls /home`
for f in /home/*; do
  mkdir -p "$f"/.kube
  # 复制kubernates连接信息
  cp -f /etc/kubernetes/admin.conf "$f"/.kube/config
  # 配置连接信息所有者为对应文件用户
  chown "${f#*/home/}":"${f#*/home/}" "$f"/.kube/config
  chown "${f#*/home/}":"${f#*/home/}" "$f"/.kube
  # 配置命令补全
#  echo '
#source <(kubeadm completion bash)
#source <(kubectl completion bash)
#source <(crictl completion bash)
#' >>"$f"/.bashrc
done

printf "\n###add kubeconfig to /root/kube/config, set kubeadm, kubectl and crictl completion\n"
export root_home=/root
mkdir -p $root_home/.kube
cp -f /etc/kubernetes/admin.conf $root_home/.kube/config

printf "\n###覆盖kubernetes目录下.kube的config###\n"
if [ -e ../.kube ]; then
  printf "\n更新kubernetes配置文件到相对路径下.kube \n"
  if ! [ -e  ../.kube/"$HOSTNAME" ]; then
      # printf "\n.kube下无当前虚拟机名称路径，重新创建 \n"
    mkdir ".kube/$HOSTNAME"
  fi
  cp -f /etc/kubernetes/admin.conf ../.kube/"$HOSTNAME"/config
fi

printf "\n###remove control plan taint\n"
kubectl describe no | grep "Taints" | awk '{print "kubectl taint nodes --all " $2 "-"}' | bash
# 修改默认的service-node-port-range 20000-40000
# sed -i '/- --service-cluster-ip-range/a \ \ \ \ - --service-node-port-range=20000-40000' kube-apiserver.yaml

#printf "\n###install cni flannel\n"
#kubectl apply -f ../cni/flannel.yml

# printf "\n###所有节点增加标签 k8s.kuboard.cn/role=etcd \n"
# kubectl label nodes "$(kubectl get no | awk 'NR!=1{print $1}')" k8s.kuboard.cn/role=etcd
# printf "\n###安装kuboard\n"
# kubectl apply -f https://addons.kuboard.cn/kuboard/kuboard-v3.yaml

#printf "\n###安装kuboard无etc版本\n"
#kubectl apply -f ../graphic-monitoring/kuboard-se.yml
#printf "\n###集群安装完毕,kuboard地址%s:30080,默认用户名密码  admin Kuboard123 \n" "$master_ip"
#printf "\n###集群master节点初始化完毕,ip:%s,\n" "$master_ip"

#printf "\n###搭建nfs-sc\n"
#kubectl apply -f ../sc_pv_pvc/sc-nfs.yaml
