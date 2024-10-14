#!/bin/bash
# 失败阻断
#set -e
# 打印脚本执行过程
set -x
# 预执行  可能会导致报错 /root/.bashrc: line 6: PS1: unbound variable
# set -u

printf "\n###add aliyun apt docker-ce repository\n"
executing_command 'apt-get update'
executing_command "apt-get -y install apt-transport-https ca-certificates curl software-properties-common"
executing_command "curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -"
executing_command "echo | add-apt-repository 'deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable'"
executing_command "apt-get update"

printf "\n###install cri\n"
cri_socket="--cri-socket="
if [[ $cri == 'containerd' ]]; then
  printf "\n###install containerd\n"
  executing_command "apt-get -y install containerd"
  if ! [ -x "$(command -v ctr)" ]; then
    printf "FAIL: ctr can not execute, install containerd error, exit\n"
    exit
  fi

  printf "\n###update containerd config\n"
  if ! [ -d "/etc/containerd" ]; then
      mkdir "/etc/containerd"
  fi
  executing_command "containerd config default | tee /etc/containerd/config.toml"
  sed -i "s@systemd_cgroup\ \=\ false@systemd_cgroup\ \=\ true@g" /etc/containerd/config.toml
  sed -i "s@SystemdCgroup \ \=\ false@SystemdCgroup \ \=\ true@g" /etc/containerd/config.toml
  sed -i "s@registry.k8s.io@registry.aliyuncs.com/google_containers@g" /etc/containerd/config.toml
  sed -i "s@runtime_type.*@runtime_type\ \=\ \"io.containerd.runtime.v1.linux\"@g" /etc/containerd/config.toml
  ## 配置国内镜像源
#  sed -i "s@config_path\ \=\ \"\"@config_path\ \=\ \"/etc/containerd/certs.d\"@g" /etc/containerd/config.toml
#  mkdir -p /etc/containerd/certs.d/docker.io    #这里的最终子文件夹名字和下面的server对应
#cat > /etc/containerd/certs.d/docker.io/hosts.toml <<EOF
#server = "https://docker.io"
#[host."https://vmhar28h.mirror.aliyuncs.com"]
#  capabilities = ["pull", "resolve"]
#EOF
  cri_socket=$cri_socket"unix:///var/run/containerd/containerd.sock"
  printf "\n###restart containerd\n"
  systemctl daemon-reload
  systemctl enable --now containerd

elif [[ $cri == 'docker' ]]; then

  printf "\n###install docker\n"
  executing_command "apt -y install docker-ce"
  ## 配置镜像仓库，cgroup驱动
  cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "http://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://registry.docker-cn.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries" : []
}
EOF
  #	重启docker
  executing_command "systemctl daemon-reload && systemctl restart docker && systemctl enable docker"

  printf "\n 安装cri_docker"
  cri_docker_version="0.3.14"
  # 获取二进制文件
  wget https://ghp.ci/https://github.com/Mirantis/cri-dockerd/releases/download/v$cri_docker_version/cri-dockerd-$cri_docker_version.amd64.tgz -O cri-dockerd.tgz
  tar -xzvf cri-dockerd.tgz && cp cri-dockerd/cri-dockerd /usr/local/bin/
  rm -rf cri-dockerd cri-dockerd.tgz
  # 获取systemd配置
  wget "${github_proxy}/Mirantis/cri-dockerd/blob/master/packaging/systemd/cri-docker.service" -o /lib/systemd/system/cri-docker.service
  wget "${github_proxy}/Mirantis/cri-dockerd/blob/master/packaging/systemd/cri-docker.socket" -o /lib/systemd/system/cri-docker.socket
  ## 修改配置文件 /lib/systemd/system/cri-docker.service
  # 注释原来的ExecStart
  sed -i 's/^\(.*ExecStart.*\)$/#\1/' /lib/systemd/system/cri-docker.service
  # 添加新的ExecStart 指定pause
  sed -i '/^\(.*ExecStart.*\)$/a ExecStart=/usr/bin/cri-dockerd --network-plugin=cni --pod-infra-container-image=registry.aliyuncs.com\/google_containers\/pause:3.8' /lib/systemd/system/cri-docker.service

  # 重启cri-docker
  executing_command "systemctl daemon-reload && systemctl restart cri-docker && systemctl enable cri-docker"
  cri_socket=$cri_socket"unix:///var/run/cri-dockerd.sock"
fi

export cri_socket
