
systemctl stop kube*
systemctl disable kube*
systemctl stop etcd
systemctl disable etcd
rm -rf /etc/systemd/system/kube*
rm -rf /etc/systemd/system/etcd
systemctl daemon-reload

kubeadm reset --force
apt purge kubeadm kubelet -y
rm -rf /var/lib/etcd
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet
rm -rf /usr/libexec/kubernetes
rm -rf /usr/local/bin/kube*
rm -rf /usr/local/bin/etcd*
rm -rf $HOME/.kube/config
rm -rf /etc/cni/
rm -rf /var/log/pods
rm -rf /var/log/containers/kube*
