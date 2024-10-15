
# 命令执行函数
executing_command() {
  i=1
  printf "\n executing command: %s\n" "$*"
  # 尝试执行三次 eval:将字符串作为命令执行并且继续执行脚本   exec:将字符串作为命令执行且会在执行结束后退出脚本执行
  while ! eval "$*" && [ "$i" -ne 3 ]; do
    printf "\n###command:%s  \n process fail number %s\n\n" "$*" "$i"
    ((i++))
  done
  # 已执行三次则退出执行
  if [ "$i" -eq 3 ]; then
    printf "\n###command:%s  \n process still fail number %s,exit\n\n" "$*" "$i"
    exit
  fi
}

# kube_version
if [ -z "${kube_version}" ]; then
#  kube_version='1.30.2'
  kube_version='last'
  export kube_version
fi

# cri
if [ -z "${cri}" ]; then
#  cri='docker'
  cri=containerd
  export cri
fi

# master_ip
if [ -z "${master_ip}" ]
then
  master_ip=$(ip a | grep -P -o '192\.168\.[0-9.]{4,8}(?=\/)' | awk 'END{printf $1}')
  export master_ip
fi

# github_proxy
if [ -z "${github_proxy}" ]
then
#  github_proxy="https://ghp.ci/https://github.com"
  github_proxy="https://github.com"
  export github_proxy
fi

### profile for bin init cluster
# 安装目录
if [ -z "$install_dir" ]
then
  install_dir=~/kube_install/$(date +"%Y.%m.%d-%H%M%S")
  export install_dir
  mkdir "$install_dir" -p
fi

# 主机IP
export host_ip=$master_ip
# 节点名称
export HOSTNAME=$(hostname)
# kubernetes 运行配置文件存放
export k8s_etc=/etc/kubernetes
# 证书存放
export K8S_SSL_Path=$k8s_etc/ssl
# service CIDR
export SERVICE_CIDR=10.1.0.0/16
# 集群CIDR POD IP
export CLUSTER_CIDR=10.244.0.0/16
# NodePort 范围
export NODE_PORT_RANGE=20000-40000
# 集群serviceIP, service CIDR的第十个
export CLUSTER_KUBERNETES_SVC_IP=10.1.0.10
# 集群IP, service CIDR的第一个
export CLUSTER_KUBERNETES_IP=10.1.0.1
