#!/bin/bash

# 安装 docker
yum install -y yum-utils device-mapper-persistent-data lvm2 wget openssl
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install docker-ce -y
dockerd >/dev/null 2>&1 &
sleep 3
docker ps

# 安装 kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget -O Bluemix_CLI_0.5.5_amd64.tar.gz 'https://plugins.ng.bluemix.net/download/bluemix-cli/0.5.5/linux64'
tar -zxf Bluemix_CLI_0.5.5_amd64.tar.gz
cd Bluemix_CLI
./install_bluemix_cli
bluemix config --usage-stats-collect false
bx plugin install container-service -r Bluemix

# 初始化
USERNAME=$1
PASSWD=$2
(echo 1) | bx login -a https://api.ng.bluemix.net -u $USERNAME -p $PASSWD
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
kubectl get nodes

# 构建面板容器
bx plugin install container-registry -r Bluemix
bx cr login
NS=$(openssl rand -base64 16 | md5sum | head -c16)
bx cr namespace-add $NS
cp /root/.bluemix/plugins/container-service/clusters/*/*.yml ./config
cp /root/.bluemix/plugins/container-service/clusters/*/*.pem ./
PEM=$(basename $(ls /root/.bluemix/plugins/container-service/clusters/*/*.pem))
cat << _EOF_ > Dockerfile
FROM alpine:latest
RUN apk add --update curl
RUN curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kubectl
RUN mkdir /root/.kube
ADD config /root/.kube/config
ADD $PEM /root/.kube/
RUN kubectl get nodes
CMD kubectl proxy --address='0.0.0.0' --accept-hosts '.*'
_EOF_
docker build -t registry.ng.bluemix.net/$NS/kube .
docker push registry.ng.bluemix.net/$NS/kube

# 创建面板运行环境
kubectl run kube --image=registry.ng.bluemix.net/$NS/kube --port=8001
kubectl expose deployment kube --type=NodePort --name=kube

# 删除构建环境
kubectl delete pod build