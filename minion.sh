#!/bin/sh

ADDR=$(ip addr | awk '/inet/ && /eth0/{sub(/\/.*$/,"",$2); print $2}')
ETCD_DISCVERY="10.91.11.202"
sudo mount -o remount,rw /dev/mapper/atomicos-root /usr/

cat <<EOF > /usr/lib/systemd/system/etcd.service
[Unit]
Description=etcd

[Service]
Environment=ETCD_DATA_DIR=/var/lib/etcd
Environment=ETCD_NAME=%m
ExecStart=/bin/etcd \
  -addr=${ADDR}:4001 \
  -peer-addr=${ADDR}:7001 \
  -discovery=http://${ETCD_DISCVERY}:4001/v2/keys/cluster
Restart=always
RestartSec=10s
EOF
systemctl daemon-reload
systemctl restart etcd.service
systemctl status etcd.service

cat <<EOF > /usr/lib/systemd/system/flannel.service
[Unit]
Requires=etcd.service
After=etcd.service

[Service]
ExecStart=/bin/flanneld -iface ${ADDR} -etcd-endpoints=http://${ETCD_DISCVERY}:4001

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable flannel.service
systemctl restart flannel.service
systemctl status flannel.service

systemctl disable docker.service

FLANNEL_SUBNET=$(ip addr show dev flannel0 | sed -nr 's/.*inet ([^ ]+).*/\1/p')
NEXT_WAIT_TIME=0
until [ '$FLANNEL_SUBNET' == '' ] || [ $NEXT_WAIT_TIME -eq 4 ]; do
    echo "Waiting to flannel"
    sleep $(( NEXT_WAIT_TIME++ ))
done
if [ '$FLANNEL_SUBNET' == '' ]; then
    echo "flanne0 doesn't exists"
    exit
fi

mkdir -p /run/flannel
cat <<EOF > /run/flannel/subnet.env
FLANNEL_SUBNET=${FLANNEL_SUBNET}
FLANNEL_MTU=1372
EOF


cat <<EOF > /usr/lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket flannel.service
Requires=docker.socket flannel.service

[Service]
Type=notify
WorkingDirectory=/etc
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-storage
EnvironmentFile=/run/flannel/subnet.env
ExecStartPre=-/usr/sbin/ip link set dev docker0 down
ExecStartPre=-/usr/sbin/ip link del dev docker0
ExecStart=/usr/bin/docker -d -H fd:// \$OPTIONS \$DOCKER_STORAGE_OPTIONS \
  --bip=\${FLANNEL_SUBNET} \
  --mtu=\${FLANNEL_MTU}
LimitNOFILE=1048576
LimitNPROC=1048576
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable docker.service
systemctl restart docker.service
systemctl status docker.service

iptables -I INPUT 1 -p tcp --dport 10250 -j ACCEPT -m comment --comment "kubelet"

cat <<EOF > /usr/lib/systemd/system/kubelet.service
[Unit]
ConditionFileIsExecutable=/bin/kubelet
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
Wants=etcd.service
After=etcd.service

[Service]
ExecStart=/bin/kubelet \
  -address=0.0.0.0 \
  -port=10250 \
  -hostname_override=${ADDR} \
  -etcd_servers=http://${ETCD_DISCVERY}:4001 \
  -logtostderr=true
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kubelet.service
systemctl restart kubelet.service
systemctl status kubelet.service

cat <<EOF > /usr/lib/systemd/system/kube-proxy.service
[Unit]
ConditionFileIsExecutable=/bin/kube-proxy
Description=Kubernetes Proxy
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
Wants=etcd.service
After=etcd.service

[Service]
ExecStart=/bin/kube-proxy \
  -etcd_servers=http://${ETCD_DISCVERY}:4001 \
  -logtostderr=true
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-proxy.service
systemctl restart kube-proxy.service
systemctl status kube-proxy.service