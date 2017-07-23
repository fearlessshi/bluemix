#!/bin/bash

# 安装 docker
tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
yum install docker-engine wget -y
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
cat << _EOF_ > Dockerfile
FROM alpine:latest
RUN apk add --update curl
RUN curl -Lo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kubectl
RUN curl -Lo Bluemix_CLI_0.5.5_amd64.tar.gz 'https://plugins.ng.bluemix.net/download/bluemix-cli/0.5.5/linux64'; tar -zxf Bluemix_CLI_0.5.5_amd64.tar.gz; cd Bluemix_CLI; ./install_bluemix_cli; cd ..; rm -rf  Bluemix_CLI*
RUN bluemix config --usage-stats-collect false
RUN bx plugin install container-service -r Bluemix
RUN (echo 1) | bx login -a https://api.ng.bluemix.net -u $USERNAME -p $PASSWD
RUN bx cs init
RUN $(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
RUN kubectl get nodes
CMD kubectl proxy --address='0.0.0.0' --accept-hosts '.*'
_EOF_
docker build -t kube:v1 .
kubectl run kube --image=kube:v1 --port=8001 --hostport=80

# 创建面板运行环境
