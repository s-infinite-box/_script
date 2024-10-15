# alpine 更改apk源
```shell
cat > /etc/apk/repositories << EOF
http://mirrors.aliyun.com/alpine/v3.16/main
http://mirrors.aliyun.com/alpine/v3.16/community

http://mirrors.aliyun.com/alpine/edge/community
http://mirrors.aliyun.com/alpine/edge/testing
EOF
```
#    安装
```shell
apk add containerd kubelet kubeadm kubectl ipvsadm cni-plugins nfs-utils
```
#    开机启动 启动服务
```shell
rc-update add containerd | rc-update add kubelet | rc-service containerd start
```


#    YUM源配置K8S
```shell
wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
```