#!/bin/bash

# 安装 unzip
wget https://coding.net/u/tprss/p/bluemix-source/git/raw/master/v2/unrar
chmod +x ./unrar
sudo mv ./unrar /usr/bin/

# 安装 kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget -O Bluemix_CLI.rar 'http://detect-10000037.image.myqcloud.com/5e3d1568-d4be-43ac-9196-3be430b82aec' #0.5.5
unrar x Bluemix_CLI.rar
cd Bluemix_CLI
sudo ./install_bluemix_cli
bluemix config --usage-stats-collect false
wget -O container-service-linux-amd64.rar 'http://detect-10000037.image.myqcloud.com/1bc1657f-5979-4c96-9d13-5c1b289c84a5'
unrar container-service-linux-amd64.rar
bx plugin install ./container-service-linux-amd64

# 初始化
echo -e -n "\n请输入用户名："
read USERNAME
echo -n '请输入密码：'
read -s PASSWD
echo -e '\n'
(echo 1) | bx login -a https://api.ng.bluemix.net -u $USERNAME -p $PASSWD
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
kubectl get nodes

# 创建构建环境
cat << _EOF_ > build.yaml
apiVersion: v1
kind: Pod
metadata:
  name: build
spec:
  containers:
  - name: centos
    image: centos:centos7
    command: ["sleep"]
    args: ["1800"]
    securityContext:
      privileged: true
  restartPolicy: Never
_EOF_
kubectl create -f build.yaml
sleep 3
(echo curl -LOs 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/v2/build.sh'; echo bash build.sh $USERNAME $PASSWD) | kubectl exec -it build /bin/bash