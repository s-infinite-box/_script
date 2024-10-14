## DESC
1. ### [docker_install](docker_install)：docker安装脚本，包括二进制安装，apt安装以及阿里华为源安装

2. ### [gitlab_repo](gitlab_repo)：gitlab仓库批量导出，转移到新gitlab以及用户导出等python脚本，使用pythonSDK

3. ### [k8s_install](k8s_install)： k8s安装脚本，支持二进制/apt安装集群组件，kubeadm/systemd启动集群

4. ### [push-release-image](push-release-image)：镜像转移python脚本，从kuboard查询当前环境镜像，拉取到本地，再上传到目标环境

5. ### [ssh-engine](ssh-engine)：go编写的基于SSH的部署工具，类似于ansible，支持自定义参数，批量执行，执行顺序编排等