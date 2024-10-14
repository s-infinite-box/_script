#!/bin/bash
set -xe
set -o pipefail


if ! [ -x "$(which etcd)" ]
then
  echo "etcd install failed"
  exit 1
fi

if ! [ -x "$(which kubelet)" ] || ! [ -x "$(which kubectl)" ]
then
  echo "kubernetes install failed"
  exit 1
fi

if ! [ -x "$(which cfssl)" ]
then
  echo "install failed, check github proxy; url: $cfssl_bin_url"
  exit 1
fi

# 创建临时证书目录
mkdir -p "${install_dir}/ssl/"
# 创建kubernetes证书目录
mkdir -p "${K8S_SSL_Path}"
# 创建systemd.service临时存放目录
mkdir -p "${install_dir}/service"
# k8s配置文件临时存放目录
mkdir -p ${install_dir}/conf

# 生成k8s组件kubeconfig函数 简化后续脚本
function gen_kube_conf() {
  cd "${install_dir}"/conf
  kubectl config \
    set-cluster kubernetes \
    --certificate-authority=$K8S_SSL_Path/ca.pem \
    --embed-certs=true \
    --server=https://$host_ip:6443 \
    --kubeconfig=${1}.kubeconfig
  kubectl config \
    set-credentials system:${1} \
    --client-certificate=$K8S_SSL_Path/${1}.pem \
    --client-key=$K8S_SSL_Path/${1}-key.pem \
    --embed-certs=true \
    --kubeconfig=${1}.kubeconfig
  kubectl config \
    set-context system:${1} \
    --cluster=kubernetes \
    --user=system:${1} \
    --kubeconfig=${1}.kubeconfig
  kubectl config \
    use-context system:${1} \
    --kubeconfig=${1}.kubeconfig
  cp ${1}.kubeconfig $k8s_etc/
}
# 生成各组件证书文件函数
function gen_ssl() {
  cd ${install_dir}/ssl
  cfssl gencert \
    -ca=${install_dir}/ssl/ca.pem \
    -ca-key=${install_dir}/ssl/ca-key.pem \
    -config=${install_dir}/ssl/ca-config.json \
    -profile=kubernetes \
    ${install_dir}/ssl/$1 |
    cfssljson -bare $2
  cp ${install_dir}/ssl/${2}* ${K8S_SSL_Path}/
}


# 创建CA根证书
cat >"${install_dir}/ssl/ca-csr.json" <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Shanghai",
      "L": "Shanghai",
      "O": "pphome",
      "OU": "pphome"
    }
  ],
  "ca": {
    "expiry": "876000h"
 }
}
EOF
# 配置ca根证书策略
cat >"${install_dir}/ssl/ca-config.json" <<EOF
{
 "signing": {
   "default": {
     "expiry": "87600h"
   },
   "profiles": {
     "kubernetes": {
       "usages": [
           "signing",
           "key encipherment",
           "server auth",
           "client auth"
       ],
       "expiry": "876000h"
     }
   }
 }
}
EOF
cd ${install_dir}/ssl
cfssl gencert -initca "${install_dir}/ssl/ca-csr.json" | cfssljson -bare ca
cp ${install_dir}/ssl/ca* ${K8S_SSL_Path}/

### etcd
# etcd csr
cat <<EOF >"${install_dir}/ssl/etcd-csr.json"
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${host_ip}",
    "${HOSTNAME}"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "SHANGHAI",
      "L": "SHANGHAI",
      "O": "pphome",
      "OU": "pphome"
    }
  ]
}
EOF
gen_ssl etcd-csr.json etcd

# 启动etcd
mkdir -p "/var/lib/etcd"
chmod 700 /var/lib/etcd
### 准备etcd.service
cat <<EOF >"${install_dir}/service/etcd.service"
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStop=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/etcd \\
 --name=${HOSTNAME} \\
 --cert-file=${K8S_SSL_Path}/etcd.pem \\
 --key-file=${K8S_SSL_Path}/etcd-key.pem \\
 --trusted-ca-file=${K8S_SSL_Path}/ca.pem \\
 --client-cert-auth \\
 --peer-cert-file=${K8S_SSL_Path}/etcd.pem \\
 --peer-key-file=${K8S_SSL_Path}/etcd-key.pem \\
 --peer-trusted-ca-file=${K8S_SSL_Path}/ca.pem \\
 --peer-client-cert-auth \\
 --initial-advertise-peer-urls=https://${host_ip}:2380 \\
 --listen-peer-urls=https://${host_ip}:2380 \\
 --listen-client-urls=https://${host_ip}:2379,https://127.0.0.1:2379 \\
 --advertise-client-urls=https://${host_ip}:2379 \\
 --initial-cluster-token=etcd-cluster \\
 --initial-cluster=${HOSTNAME}=https://${host_ip}:2380 \\
 --initial-cluster-state=new \\
 --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
# systemd启动etcd
cp "${install_dir}/service/etcd.service" /etc/systemd/system/etcd.service
systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd

### 检查etcd
etcdctl \
  --endpoints="${host_ip}":2379,127.0.0.1:2379 \
  --cacert=${K8S_SSL_Path}/ca.pem \
  --cert=${K8S_SSL_Path}/etcd.pem \
  --key=${K8S_SSL_Path}/etcd-key.pem \
  endpoint status --write-out=table

### api-server csr
cat <<EOF >"${install_dir}/ssl/apiserver-csr.json"
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${host_ip}",
    "${HOSTNAME}",
    "$CLUSTER_KUBERNETES_IP",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "SHANGHAI",
      "L": "SHANGHAI",
      "O": "pphome",
      "OU": "pphome"
    }
  ]
}
EOF
gen_ssl apiserver-csr.json apiserver
##  监控相关证书 可省略
cat <<EOF >${install_dir}/ssl/aggregator-csr.json
{
  "CN": "aggregator",
  "hosts": [
    "${host_ip}",
    "$HOSTNAME"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "SHANGHAI",
      "L": "SHANGHAI",
      "O": "pphome",
      "OU": "pphome"
    }
  ]
}
EOF
gen_ssl aggregator-csr.json aggregator
### kube-apiserver systemd.service
cat <<EOF >"${install_dir}/service/kube-apiserver.service"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --secure-port=6443 \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --api-audiences=api,istio-ca \\
  --authorization-mode=Node,RBAC \\
  --bind-address=${host_ip} \\
  --client-ca-file=${K8S_SSL_Path}/ca.pem \\
  --endpoint-reconciler-type=lease \\
  --etcd-cafile=${K8S_SSL_Path}/ca.pem \\
  --etcd-certfile=${K8S_SSL_Path}/apiserver.pem \\
  --etcd-keyfile=${K8S_SSL_Path}/apiserver-key.pem \\
  --etcd-servers=https://${host_ip}:2379 \\
  --kubelet-certificate-authority=${K8S_SSL_Path}/ca.pem \\
  --kubelet-client-certificate=${K8S_SSL_Path}/apiserver.pem \\
  --kubelet-client-key=${K8S_SSL_Path}/apiserver-key.pem \\
  --service-account-issuer=https://kubernetes.default.svc \\
  --service-account-signing-key-file=${K8S_SSL_Path}/ca-key.pem \\
  --service-account-key-file=${K8S_SSL_Path}/ca.pem \\
  --service-cluster-ip-range=$SERVICE_CIDR \\
  --service-node-port-range=$NODE_PORT_RANGE \\
  --tls-cert-file=${K8S_SSL_Path}/apiserver.pem \\
  --tls-private-key-file=${K8S_SSL_Path}/apiserver-key.pem \\
  --requestheader-client-ca-file=${K8S_SSL_Path}/ca.pem \\
  --requestheader-allowed-names=front-proxy-client \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --proxy-client-cert-file=$K8S_SSL_Path/aggregator.pem \\
  --proxy-client-key-file=$K8S_SSL_Path/aggregator-key.pem \\
  --enable-aggregator-routing=true \\
  --v=2
Restart=always
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
### systemd启动kube-apiserver
cp "${install_dir}/service/kube-apiserver.service" /etc/systemd/system/kube-apiserver.service
systemctl daemon-reload
systemctl enable kube-apiserver
systemctl restart kube-apiserver
### 验证api-server
curl -k https://${host_ip}:6443/healthz \
  --cacert ${K8S_SSL_Path}/ca.pem \
  --cert ${K8S_SSL_Path}/apiserver.pem \
  --key ${K8S_SSL_Path}/apiserver-key.pem

### kubectl admin 证书
cat <<EOF >"${install_dir}/ssl/admin-csr.json"
{
  "CN": "admin",
  "hosts": [
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "SHANGHAI",
      "L": "SHANGHAI",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
gen_ssl admin-csr.json admin
# kubeconfig
kubectl config \
  set-cluster kubernetes \
  --certificate-authority="${K8S_SSL_Path}/ca.pem" \
  --embed-certs=true \
  --server="https://${host_ip}:6443" \
  --kubeconfig=kubectl.kubeconfig
kubectl config \
  set-credentials admin \
  --client-certificate=${K8S_SSL_Path}/admin.pem \
  --client-key=${K8S_SSL_Path}/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig
kubectl config \
  set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig
mkdir -p ~/.kube
cp kubectl.kubeconfig ~/.kube/config
cp kubectl.kubeconfig $k8s_etc/admin.conf

### controller-manager csr
cat <<EOF >${install_dir}/ssl/kube-controller-manager-csr.json
{
  "CN": "system:kube-controller-manager",
  "hosts": [
    "127.0.0.1",
    "$host_ip",
    "$HOSTNAME"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "SHANGHAI",
      "L": "SHANGHAI",
      "O": "system:kube-controller-manager",
      "OU": "System"
    }
  ]
}
EOF
gen_ssl kube-controller-manager-csr.json kube-controller-manager
cd ${install_dir}/ssl
gen_kube_conf kube-controller-manager
### systemd 启动controller-manager
cat <<EOF >${install_dir}/service/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --allocate-node-cidrs=true \\
  --cluster-cidr=$CLUSTER_CIDR \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=$K8S_SSL_Path/ca.pem \\
  --cluster-signing-key-file=$K8S_SSL_Path/ca-key.pem \\
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --node-cidr-mask-size=24 \\
  --root-ca-file=$K8S_SSL_Path/ca.pem \\
  --service-account-private-key-file=$K8S_SSL_Path/ca-key.pem \\
  --service-cluster-ip-range=$SERVICE_CIDR \\
  --use-service-account-credentials=true \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cp ${install_dir}/service/kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl restart kube-controller-manager

### scheduler
cat <<EOF >${install_dir}/ssl/kube-scheduler-csr.json
{
  "CN": "system:kube-scheduler",
  "hosts": [
    "127.0.0.1",
    "$host_ip",
    "$HOSTNAME"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "HuBei",
      "L": "WuHan",
      "O": "system:kube-scheduler",
      "OU": "System"
    }
  ]
}
EOF
gen_ssl kube-scheduler-csr.json kube-scheduler
### scheduler 配置
gen_kube_conf kube-scheduler
### systemd 启动 scheduler
cat <<EOF >${install_dir}/service/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --authentication-kubeconfig=$k8s_etc/kube-scheduler.kubeconfig \\
  --authorization-kubeconfig=$k8s_etc/kube-scheduler.kubeconfig \\
  --bind-address=0.0.0.0 \\
  --kubeconfig=$k8s_etc/kube-scheduler.kubeconfig \\
  --leader-elect=true \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cp ${install_dir}/service/kube-scheduler.service /etc/systemd/system/kube-scheduler.service
systemctl daemon-reload
systemctl enable kube-scheduler
systemctl restart kube-scheduler

### kubelet
cat <<EOF >${install_dir}/ssl/kubelet-csr.json
{
    "CN": "system:node",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
      "127.0.0.1",
      "${host_ip}",
      "${HOSTNAME}"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "HuBei",
        "L": "WuHan",
        "O": "system:nodes",
        "OU": "System"
      }
    ]
}
EOF
gen_ssl kubelet-csr.json kubelet
cd ${install_dir}/conf
### kubelet config
## 注意 system:node:$host_ip
kubectl config \
  set-cluster kubernetes \
  --certificate-authority=$K8S_SSL_Path/ca.pem \
  --embed-certs=true \
  --server=https://$host_ip:6443 \
  --kubeconfig=kubelet.kubeconfig

kubectl config \
  set-credentials system:node \
  --client-certificate=$K8S_SSL_Path/kubelet.pem \
  --client-key=$K8S_SSL_Path/kubelet-key.pem \
  --embed-certs=true \
  --kubeconfig=kubelet.kubeconfig
## 注意 --user=system:node
kubectl config \
  set-context system:node \
  --cluster=kubernetes \
  --user=system:node \
  --kubeconfig=kubelet.kubeconfig
kubectl config \
  use-context system:node \
  --cluster=kubernetes \
  --kubeconfig=kubelet.kubeconfig
cp kubelet.kubeconfig $k8s_etc/

### kubelet-config.yaml
## https://kubernetes.io/zh-cn/docs/reference/config-api/kubelet-config.v1beta1/
cat <<EOF >${install_dir}/conf/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: $K8S_SSL_Path/ca.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: systemd
cgroupsPerQOS: true
clusterDNS:
- $CLUSTER_KUBERNETES_SVC_IP
clusterDomain: cluster.local
configMapAndSecretChangeDetectionStrategy: Watch
containerLogMaxFiles: 3
containerLogMaxSize: 10Mi
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 300Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 40s
hairpinMode: hairpin-veth
healthzBindAddress: 0.0.0.0
healthzPort: 10248
httpCheckFrequency: 40s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
kubeAPIBurst: 100
kubeAPIQPS: 50
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeLeaseDurationSeconds: 40
nodeStatusReportFrequency: 1m0s
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
port: 10250
# disable readOnlyPort
readOnlyPort: 0
resolvConf: /etc/resolv.conf
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
tlsCertFile: $K8S_SSL_Path/kubelet.pem
tlsPrivateKeyFile: $K8S_SSL_Path/kubelet-key.pem
EOF
cp ${install_dir}/conf/kubelet-config.yaml /etc/kubernetes/kubelet-config.yaml
### systemd 启动 kubelet
mkdir -p /var/lib/kubelet
## https://kubernetes.io/zh-cn/docs/reference/command-line-tools-reference/kubelet/
cat <<EOF >${install_dir}/service/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \\
  --config=/etc/kubernetes/kubelet-config.yaml \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --hostname-override=${HOSTNAME} \\
  --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.9 \\
  --root-dir=/var/lib/kubelet \\
  --cert-dir=/etc/kubernetes/ssl \\
  --v=2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cp ${install_dir}/service/kubelet.service /etc/systemd/system/kubelet.service
systemctl daemon-reload
systemctl enable kubelet
systemctl restart kubelet

### kube-proxy cilium 可以忽略该组件
#cat <<EOF >${install_dir}/ssl/kube-proxy-csr.json
#{
#    "CN": "system:kube-proxy",
#    "key": {
#        "algo": "rsa",
#        "size": 2048
#    },
#    "hosts": [
#      "127.0.0.1",
#      "${host_ip}",
#      "${HOSTNAME}"
#    ],
#    "names": [
#      {
#        "C": "CN",
#        "ST": "HuBei",
#        "L": "WuHan",
#        "O": "system:nodes",
#        "OU": "System"
#      }
#    ]
#}
#EOF
#gen_ssl kube-proxy-csr.json kube-proxy
#gen_kube_conf kube-proxy
#
#cat <<EOF >${install_dir}/conf/kube-proxy-config.yaml
#kind: KubeProxyConfiguration
#apiVersion: kubeproxy.config.k8s.io/v1alpha1
#bindAddress: 0.0.0.0
#clientConnection:
#  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
#clusterCIDR: "$CLUSTER_CIDR"
#conntrack:
#  maxPerCore: 32768
#  min: 131072
#  tcpCloseWaitTimeout: 1h0m0s
#  tcpEstablishedTimeout: 24h0m0s
#healthzBindAddress: 0.0.0.0:10256
#metricsBindAddress: 0.0.0.0:10249
## mode: "ipvs"
#EOF
#cp ${install_dir}/conf/kube-proxy-config.yaml $k8s_etc/
#mkdir -p /var/lib/kube-proxy
#cat <<EOF >${install_dir}/service/kube-proxy.service
#[Unit]
#Description=Kubernetes Kube-Proxy Server
#Documentation=https://github.com/GoogleCloudPlatform/kubernetes
#After=network.target
#
#[Service]
## kube-proxy 根据 --cluster-cidr 判断集群内部和外部流量
### 指定 --cluster-cidr 或 --masquerade-all 选项后
### kube-proxy 会对访问 Service IP 的请求做 SNAT
#WorkingDirectory=/var/lib/kube-proxy
#ExecStart=/usr/local/bin/kube-proxy \\
#  --config=/etc/kubernetes/kube-proxy-config.yaml
#Restart=always
#RestartSec=5
#LimitNOFILE=65536
#
#[Install]
#WantedBy=multi-user.target
#EOF
#cp ${install_dir}/service/kube-proxy.service /etc/systemd/system/kube-proxy.service
#systemctl daemon-reload
#systemctl enable kube-proxy
#systemctl restart kube-proxy

### coredns
cat <<EOF >${install_dir}/conf/coredns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
  labels:
      kubernetes.io/cluster-service: "true"
      addonmanager.kubernetes.io/mode: Reconcile
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: Reconcile
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
- apiGroups:
  - discovery.k8s.io
  resources:
  - endpointslices
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: EnsureExists
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
  labels:
      addonmanager.kubernetes.io/mode: EnsureExists
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: k8s-app
                    operator: In
                    values: ["kube-dns"]
              topologyKey: kubernetes.io/hostname
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        kubernetes.io/os: linux
      containers:
      - name: coredns
        image: registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:v1.10.1
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 300Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: $CLUSTER_KUBERNETES_SVC_IP
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF
kubectl apply -f ${install_dir}/conf/coredns.yaml

## 创建角色绑定 避免kubelet kubectl相关权限问题
kubectl create clusterrolebinding system-node-role-bound --clusterrole=system:node --group=system:nodes
kubectl create clusterrolebinding kubernetes --clusterrole=cluster-admin --user=kubernetes

cd $curr_dir

set +xue
set +o pipefail
