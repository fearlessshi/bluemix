#!/bin/bash

# 安装 kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/Bluemix_CLI_0.5.5_amd64.tar.gz'
tar -zxf Bluemix_CLI_0.5.5_amd64.tar.gz
cd Bluemix_CLI
sudo ./install_bluemix_cli
bluemix config --usage-stats-collect false
bx plugin install container-service -r Bluemix

# 初始化
echo -n '请输入用户名：'
read USERNAME
echo -n '请输入密码：'
read -s PASSWD
(echo 1) | bx login -a https://api.ng.bluemix.net -u $USERNAME -p $PASSWD
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
kubectl get nodes