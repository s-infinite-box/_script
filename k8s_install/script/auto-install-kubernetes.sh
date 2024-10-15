#!/bin/bash
# 失败阻断
#set -e
# 打印脚本执行过程
set -x
# 预执行  可能会导致报错 /root/.bashrc: line 6: PS1: unbound variable
# set -u

### main
# 当前目录
export curr_dir=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
. $curr_dir/init_profile.sh

. $curr_dir/init_node.sh

. $curr_dir/install_cri.sh

case $get_kube_type in
  apt)
    . install_kube_apt.sh
    ;;
  bin)
    . install_kube_bin.sh
    ;;
  *)
    echo -e '\033[31;1m WARNING: get_kube_type is empty, get kube by apt'
    . install_kube_apt.sh
    ;;
esac

case $init_type in
  bin|systemd)
    if [ $get_kube_type != "bin" ]
    then
      echo -e '\033[31;1m WARNING: init_type is bin, but get_kube_type not bin, exit''
      exit 1
    fi
    . init_cluster_by_systemd.sh
  ;;
  kubeadm)
    . init_cluster_by_kubeadm.sh
  ;;
  # 手动安装，只初始化节点，默认按手动处理
  Manual|manual|*)
    echo 'no proces'
    . init_cluster_by_kubeadm.sh
  ;;
esac

set +x