#!/bin/bash

# 安装 docker
yum install -y yum-utils device-mapper-persistent-data lvm2 wget openssl
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install docker-ce -y
dockerd >/dev/null 2>&1 &
sleep 3

# 安装 kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget -O Bluemix_CLI_amd64.tar.gz 'https://plugins.ng.bluemix.net/download/bluemix-cli/0.6.5/linux64'
tar -zxf Bluemix_CLI_amd64.tar.gz
cd Bluemix_CLI
./install_bluemix_cli
bluemix config --usage-stats-collect false
bx plugin install container-service -r Bluemix

# 初始化
AKN=$1
AK=$(echo $2 | base64 -d)
PPW=$3
SPW=$4
REGION=$5
IP=$6
BBR=$7
export BLUEMIX_API_KEY=$AK
(echo 1; echo no) | bx login -a https://api.${REGION}.bluemix.net
(echo 1; echo 1) | bx target --cf
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
bx iam api-key-delete $AKN

# 初始化镜像库
bx plugin install container-registry -r Bluemix
bx cr login
for name in $(bx cr namespace-list | grep del_); do (echo y) | bx cr namespace-rm $name; done
NS=del_$(openssl rand -base64 16 | md5sum | head -c16)
bx cr namespace-add $NS

# 构建面板容器
cp /root/.bluemix/plugins/container-service/clusters/*/*.yml ./config
cp /root/.bluemix/plugins/container-service/clusters/*/*.pem ./
PEM=$(basename $(ls /root/.bluemix/plugins/container-service/clusters/*/*.pem))

wget -O caddy.tar.gz https://caddyserver.com/download/linux/amd64
tar -zxf caddy.tar.gz
chmod +x ./caddy

cp /usr/local/bin/kubectl ./

cat << _EOF_ > Caddyfile
0.0.0.0:80
gzip
proxy /$PPW/ 127.0.0.1:8001
_EOF_

cat << _EOF_ > run.sh
kubectl proxy --accept-hosts '.*' --api-prefix=/$PPW/ &
caddy -conf /etc/caddy/Caddyfile
_EOF_

cat << _EOF_ > Dockerfile
FROM alpine:latest
RUN apk add --update ca-certificates
ADD kubectl /usr/local/bin/
RUN mkdir /root/.kube
ADD config /root/.kube/config
ADD $PEM /root/.kube/
ADD caddy /usr/local/bin/
RUN mkdir /etc/caddy
ADD Caddyfile /etc/caddy/
ADD run.sh /root/
CMD sh /root/run.sh
_EOF_

docker build -t $USERNAME/registry.${REGION}.bluemix.net/$NS/kube:latest .
while ! bx cr image-list | grep -q "registry.${REGION}.bluemix.net/$NS/kube:latest"
do
    docker push $USERNAME/registry.${REGION}.bluemix.net/$NS/kube:latest
done

# 创建面板运行环境
kubectl run kube --image=registry.${REGION}.bluemix.net/$NS/kube --port=80
kubectl expose deployment kube --type=LoadBalancer --name=kube --external-ip $IP

# 构建 SS 容器
cat << _EOF_ >Dockerfile
FROM easypi/shadowsocks-libev
ENV SERVER_PORT 443
ENV METHOD aes-256-cfb
ENV PASSWORD $SPW
_EOF_
docker build -t registry.${REGION}.bluemix.net/$NS/ss:latest .
while ! bx cr image-list | grep -q "registry.${REGION}.bluemix.net/$NS/ss:latest"
do
    docker push registry.${REGION}.bluemix.net/$NS/ss:latest
done

# 创建 BBR 构建文件
cat << _EOF_ > bbr.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: bbr 
  name: bbr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bbr
  template:
    metadata:
      labels:
        app: bbr
      name: bbr
    spec:
      containers:
      - env:
        - name: TARGET_HOST
          value: SS_IP
        - name: TARGET_PORT
          value: "443"
        - name: BIND_PORT
          value: "443"
        image: wuqz/lkl:latest
        name: bbr
        securityContext:
          privileged: true
      restartPolicy: Always
_EOF_

# 创建 SS 运行环境
kubectl run ss --image=registry.${REGION}.bluemix.net/$NS/ss --port=443
if $BBR; then
    kubectl expose deployment ss --name=ss
    sed -i "s/SS_IP/$(kubectl get svc ss -o=custom-columns=IP:.spec.clusterIP | tail -n1)/g" bbr.yaml
    kubectl create -f bbr.yaml
    kubectl expose deployment bbr --type=LoadBalancer --port=443 --name=ss-tcp --external-ip $IP
else
    kubectl expose deployment ss --type=LoadBalancer --name=ss-tcp --external-ip $IP
fi
kubectl expose deployment ss --type=LoadBalancer --name=ss-udp --external-ip $IP --protocol="UDP"

# 删除构建环境
kubectl delete pod build