## k8s bash 安装脚本

#### 1. 背景：

    之前在刚学习k8s的时候，安装集群用了几个周才搞明白，后来把安装的过程写成了bash脚本，用于日常开发和各种环境搭建，后来尝试了二进制安装启动集群，以及新的cilium插件并写了很多散的脚本，后来将各个脚本整合了以下就有了这个项目

    如果你想快速搭建自己的本地开发环境，不建议使用这个脚本，可以尝试k3s/rke或者kind等工具；如果你是一个初学者并且有一定bash基础，可以参考一下这个脚本搭建自己的环境，这将有利于你对k8s组件/运行原理有一定更深的认识

#### 2. 使用

目前验证环境都在ubuntu20.04，使用官方的server镜像和云镜像都可以，其他OS暂未认证，理论上二进制安装systemd启动集群跟操作系统无关，只要有systemd就可以

```shell
# 使用默认配置
./auto-install-kubernetes.sh
# 添加自定义属性，systemd启动
get_kube_type=bin init_type=systemd ./auto-install-kubernetes.sh
```

#### 3. 执行流程说明

> 1. 属性初始化：下面概略介绍下，具体可以看文件：init_profile.sh，注释写的比较清楚，如果是学习用可以直接用默认配置
>    1. 安装配置：cri（docker/containerd），k8s组件（api-server，控制器/调度器，kubelet等）安装方式（二进制/apt），github代理，安装相关配置文件目录（systemd启动集群的一些证书/service文件和集群组件的配置）等
>    2. 集群属性：节点名称，主机IP等
> 2. 节点初始化：关防火墙，swap，时间同步，配置内核参数
> 3. 安装cri运行时：目前支持docker和containerd两种，docker会安装cri-docker
> 4. 安装k8s组件：
>    1. apt安装：使用阿里的源，无需梯子，后续支持下apk和yum
>    2. 二进制安装：直接下载二进制文件，需要梯子，没有梯子大概10-20kb/s
> 5. 集群初始化：
>    1. kubeadm init，k8s组件使用静态pod启动
>    2. systemd启动组件创建集群，注意此处不会创建kube_proxy，如果需要可手动创建，systemd需要二进制安装k8s组件
> 6. cni安装
>    1. cilium，使用cilium install安装，底层走的helm，目前看cilium自动探测是否有kube_porxy并开启替换kube_proxy特性
>    2. flannel，如果创建成功但是node还是noready，确认下是不是没有kube_proxy，目前二进制那暂时注释了kube_proxy的创建逻辑，可以自行手动创建



#### 后续进一步完善的功能

> 适配多节点
> 支持外部etcd
> apt安装支持kuberntes原始源，需要梯子但是可以安装更新的版本
> systemd启动集群支持动态配置是否安装kube_proxy
