#!/bin/bash
# 失败阻断
#set -e
# 打印脚本执行过程
set -x
# 预执行  可能会导致报错 /root/.bashrc: line 6: PS1: unbound variable
# set -u
printf "\n###kubernates install start\n"

rl=$(whoami)
printf "\n current user is %s\n" "$rl"
if ! [ "root" == "$rl" ]; then
  printf "\n FAIL: require root, exit\n"
  exit
fi

os=$(cat /etc/issue)
printf "\n current os info: \n%s\n" "$os"

printf "\nHOSTNAME: %s, master_ip: %s\n" "$HOSTNAME" "$master_ip"

printf "\n### systemctl disable ufw\n"
if ! systemctl disable ufw; then
  printf "\n\n#################\n\n FAIL: disable ufw error \n\n#################\n\n"
fi

printf "\n### set sync time \n"
executing_command 'apt-get update'
executing_command 'apt install -y ntpdate'
executing_command 'ntpdate time1.aliyun.com'

printf "\n###update hosts\n"

executing_command "sed -i '1i $master_ip $HOSTNAME' /etc/hosts"

printf "\n###disable swap and update fstab\n"
#sed -d "s/^.UUID=.*swap.*sw.*/" /etc/fstab
executing_command 'swapoff -a'
executing_command "sed -i 's/^\(.*swap.*\)$/#\1/' /etc/fstab"

printf "\n###update kernel config\n"
cat >>/etc/modules-load.d/ipvs.conf <<EOF
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack #内核小于4.18，把这行改成nf_conntrack_ipv4
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF

cat >>/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# 设置所需的 sysctl 参数，参数在重新启动后保持不变
cat >/etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF

cat > /etc/sysctl.d/90-kubelet.conf << EOF
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
EOF

sysctl -p /etc/sysctl.d/90-kubelet.conf
sudo modprobe overlay
sudo modprobe br_netfilter
sysctl --system
