### 1. 配置网络
```yaml
    eth1:
      addresses: [192.168.166.77/24]
      dhcp4: no
      optional: true
    eth2:
      addresses: [192.168.177.77/24]
      dhcp4: no
      optional: true
    eth3:
      addresses: [192.168.188.77/24]
      dhcp4: no
      optional: true
```
### 2. 数据盘
```powershell
New-VHD -SizeBytes 120GB -Path Q:\vm_data\66.vhdx
New-VHD -SizeBytes 120GB -Path Q:\vm_data\66.vhdx
New-VHD -SizeBytes 120GB -Path Q:\vm_data\88.vhdx

Add-VMHardDiskDrive -VMName 66 -Path Q:\vm_data\66.vhdx
Add-VMHardDiskDrive -VMName 77 -Path Q:\vm_data\77.vhdx
Add-VMHardDiskDrive -VMName 88 -Path Q:\vm_data\88.vhdx

Remove-VMHardDiskDrive -VMName 66 -Path R:\vm_data\66.vhdx
Remove-VMHardDiskDrive -VMName 77 -Path R:\vm_data\77.vhdx
Remove-VMHardDiskDrive -VMName 88 -Path R:\vm_data\88.vhdx
```
### 3. 配置共享目录
```shell
mkdir -p /root/p /root/r
cat >> /etc/fstab <<EOF
//192.168.188.1/p /root/p cifs username=Administrator,password=22561,file_mode=0755,dir_mode=0755 0 0
//192.168.188.1/q /root/q cifs username=Administrator,password=22561,file_mode=0755,dir_mode=0755 0 0
EOF
mount -a
echo 'p_dir=/root/p pphome_bashrc="${p_dir}/pphome/linux/bashrc.d";. ${pphome_bashrc}/vm-ub.bashrc' >> ~/.bashrc
bash
### 
hostnamectl set-hostname 
```
### 4. 挂载数据盘
```shell
lsblk | grep 500G | awk '{print "mkfs.ext4 /dev/" $1}' | bash 
mkdir /root/vm_data  
echo "UUID=\"$(ll /dev/disk/by-uuid | grep $(lsblk | grep 500G | awk '{print $1}') | awk '{print $9}')\" /root/vm_data ext4 errors=remount-ro 0 0" >> /etc/fstab 
mount -a
```
### 5. 创建集群
```shell
kubeadm init \
--image-repository registry.cn-hangzhou.aliyuncs.com/google_containers \
--service-cidr=10.1.0.0/16 \
--pod-network-cidr=10.244.0.0/16 \
--apiserver-advertise-address=192.168.188.88 \
--apiserver-cert-extra-sans=127.0.0.1,ub66,ub77,ub88,192.168.188.66,192.168.188.77,192.168.188.88 \
--cri-socket=unix:///var/run/cri-dockerd.sock  \
--kubernetes-version=1.28.2  \
--upload-certs --token asdfgh.asdfghjklasdfghj \
--control-plane-endpoint 192.168.188.88 \
--token-ttl 0 -v 9

kubeadm join 192.168.188.88:6443 --token asdfgh.asdfghjklasdfghj \
--discovery-token-ca-cert-hash sha256:8a639ce66f02ef3b1ef3c18a1895191ab5544d1bac65a54c48451496fa70f3dc \
--control-plane \
--certificate-key c42724f996f217a8d165737242921111a8475a80b512a81cef84a73febf39d4b \
--cri-socket=unix:///var/run/cri-dockerd.sock \
--apiserver-advertise-address 192.168.188.77

节点最大容器数
sed -i '1i maxPods: 520' /var/lib/kubelet/config.yaml && systemctl restart kubelet
node port range
sed -i '/- --service-cluster-ip-range/a \ \ \ \ - --service-node-port-range=20000-40000' /etc/kubernetes/manifests/kube-apiserver.yaml

export root_home=/root
mkdir -p $root_home/.kube
cp -f /etc/kubernetes/admin.conf $root_home/.kube/config

CILIUM_CLI_VERSION=$(wget -qO- -t1 -T2 "https://api.github.com/repos/cilium/cilium-cli/releases/latest" | jq -r '.tag_name')
CLI_ARCH=amd64
curl -L --fail --remote-name-all https://hub.nuaa.cf/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin && rm -rf cilium-linux-${CLI_ARCH}.tar.gz
cilium install
kubectl scale deployment -n kube-system coredns --replicas 1
cilium status
kubectl get po -A -w

kubeadm init phase upload-certs --upload-certs 

```
### 6. 搭建scaleio
  
192.168.188.88 ub88
192.168.188.77 ub77
192.168.188.66 ub66 
