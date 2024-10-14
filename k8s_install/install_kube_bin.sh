
### https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.29.md#downloads-for-v1293

if [ -z "${kube_version}" ]
then
  exit 1
fi
cd ${install_dir} || exit
executing_command apt install conntrack -y
kubernetes_bin_url="https://cdn.dl.k8s.io/release/v${kube_version}/kubernetes-server-linux-amd64.tar.gz"
k8s_file_name="k8s.tgz"
executing_command curl -L --fail --remote-name-all "$kubernetes_bin_url" -o $k8s_file_name
executing_command tar -xzvf $k8s_file_name
executing_command prefix="kubernetes/server/bin"
executing_command cp $prefix/kube-apiserver $prefix/kube-proxy $prefix/kube-scheduler $prefix/kube-controller-manager $prefix/kubelet $prefix/kubectl $prefix/kubeadm /usr/local/bin/
executing_command rm -rf kubernetes $k8s_file_name


cfssl_version="1.6.5"
cfssl_bin_url="${github_proxy}/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_amd64"
executing_command curl -L --fail --remote-name-all  "$cfssl_bin_url" -o /usr/local/bin/cfssl
executing_command curl -L --fail --remote-name-all  "${github_proxy}/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_amd64" /usr/local/bin/cfssljson

# etcd二进制文件获取
# 组、仓库、架构和包名
github_group="etcd-io"
github_repo="etcd"
# 获取最新版本号
REPO_LATEST_VERSION=$(wget -qO- -t1 -T2 "https://api.github.com/repos/${github_group}/${github_repo}/releases/latest" | jq -r .tag_name)
while [ -z "$REPO_LATEST_VERSION" ]; do
    REPO_LATEST_VERSION=$(wget -qO- -t1 -T2 "https://api.github.com/repos/${github_group}/${github_repo}/releases/latest" | jq -r .tag_name)
done
PKG_NAME=etcd-${REPO_LATEST_VERSION}-linux-amd64
# 下载最新版本  使用国内github镜像站
etcd_bin_url="${github_proxy}/${github_group}/${github_repo}/releases/download/${REPO_LATEST_VERSION}/$PKG_NAME.tar.gz"
curl -L --fail --remote-name-all $etcd_bin_url -o $PKG_NAME.tar.gz
tar -xzvf $PKG_NAME.tar.gz
cp $PKG_NAME/etcd $PKG_NAME/etcdctl $PKG_NAME/etcdutl /usr/local/bin/
rm -rf $PKG_NAME $PKG_NAME.tar.gz

chmod +x /usr/local/bin/cfssl* /usr/local/bin/kube* /usr/local/bin/etcd*
cd $curr_dir || exit
