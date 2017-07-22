#!/bin/bash

# 安装 unzip
wget http://git.oschina.net/znxe7oyjp/znxe7oyjp/raw/master/unzip
chmod +x ./unzip
sudo mv ./unzip /usr/bin/

# 安装 kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget 'http://git.oschina.net/znxe7oyjp/znxe7oyjp/raw/master/Bluemix_CLI.zip' #0.5.5
unzip Bluemix_CLI.zip
cd Bluemix_CLI
sudo ./install_bluemix_cli
bluemix config --usage-stats-collect false
wget http://git.oschina.net/znxe7oyjp/znxe7oyjp/raw/master/container-service-linux-amd64.zip
unzip container-service-linux-amd64.zip
bx plugin install ./container-service-linux-amd64

# 初始化
echo -n '请输入用户名：'
read USERNAME
echo -n '请输入密码：'
read -s PASSWD
echo ''
(echo 1) | bx login -a https://api.ng.bluemix.net -u $USERNAME -p $PASSWD
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
kubectl get nodes