
printf "\n###add apt kubernates aliyun repository \n"
executing_command "apt-get install -y apt-transport-https"
executing_command "curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -"
cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
executing_command "apt-get update"
# apt-cache madison
if ! [[ $kube_version == 'last' ]]; then
  kube_aptversion_str="=$kube_version-00"
fi
printf "\n### sudo apt-get install -y kubelet$kube_aptversion_str  kubeadm$kube_aptversion_str kubectl$kube_aptversion_str\n"
executing_command "sudo apt-get install -y kubelet$kube_aptversion_str kubeadm$kube_aptversion_str kubectl$kube_aptversion_str"
echo "check command kubeadm, kubectl"

if ! [ -x "$(command -v kubeadm)" ]; then
  echo "FAIL: kubeadm can not execute, install kubeadm error, exit"
  exit
fi

if ! [ -x "$(command -v kubectl)" ]; then
  echo "FAIL: kubectl can not execute, install kubectl error, exit"
  exit
fi
if [[ $cri == 'containerd' ]]; then
  printf "\n###update crictl config\n"
  crictl config runtime-endpoint unix:///run/containerd/containerd.sock
  crictl config image-endpoint unix:///run/containerd/containerd.sock
  crictl config timeout 30
  systemctl daemon-reload && systemctl restart containerd
fi

# 锁定kubenetes版本
executing_command "apt-mark hold kubeadm kubectl kubelet"
#echo '
#source <(kubeadm completion bash)
#source <(kubectl completion bash)
#source <(crictl completion bash)
## 别名及别名命令提示
#alias k=kubectl
#complete -o default -F __start_kubectl k
#' >>/root/.bashrc

