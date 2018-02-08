#!/bin/bash

# 定义参数检查
paras=$@
function checkPara(){
    local p=$1
    for i in $paras; do if [[ $i == $p ]]; then return; fi; done
    false
}

# 设定区域
REGION=ng
checkPara 'au' && REGION=au-syd # Sydney, Australia
checkPara 'uk' && REGION=eu-gb # London, England
checkPara 'de' && REGION=eu-de # Frankfurt, Germany

# 检查 BBR 参数
BBR=false
checkPara 'bbr' && BBR=true

# 安装 unrar
#wget https://coding.net/u/tprss/p/bluemix-source/git/raw/master/v2/unrar
#chmod +x ./unrar
#sudo mv ./unrar /usr/bin/

# 安装 kubectl
#wget -O kubectl.rar 'http://detect-10000037.image.myqcloud.com/5c964783-429d-4e31-a286-6580c97d4ac1'
#unrar x kubectl.rar
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# 安装 Bluemix CLI 及插件
wget -O Bluemix_CLI_amd64.tar.gz 'https://plugins.ng.bluemix.net/download/bluemix-cli/0.6.5/linux64'
tar -zxf Bluemix_CLI_amd64.tar.gz
cd Bluemix_CLI
./install_bluemix_cli
bluemix config --usage-stats-collect false
bx plugin install container-service -r Bluemix

# 初始化
#echo -e -n "\n请输入用户名："
#read USERNAME
#echo -n '请输入密码：'
#read -s PASSWD
#echo -e '\n'
#(echo 1; echo no) | bx login -a https://api.${REGION}.bluemix.net -u $USERNAME -p $PASSWD
bx login -a https://api.${REGION}.bluemix.net
(echo 1; echo 1) | bx target --cf
bx cs init
$(bx cs cluster-config $(bx cs clusters | grep 'normal' | awk '{print $1}') | grep 'export')
PPW=$(openssl rand -base64 12 | md5sum | head -c12)
SPW=$(openssl rand -base64 12 | md5sum | head -c12)
AKN=del_$(openssl rand -base64 12 | md5sum | head -c5)
AK=$(bx iam api-key-create $AKN | tail -1 | awk '{print $3}' | base64)

# 尝试清除以前的构建环境
kubectl delete pod build 2>/dev/null
kubectl delete deploy kube ss bbr 2>/dev/null
kubectl delete svc kube ss ss-tcp ss-udp 2>/dev/null
kubectl delete rs -l run=kube | grep 'deleted' --color=never
kubectl delete rs -l run=ss | grep 'deleted' --color=never
kubectl delete rs -l run=bbr | grep 'deleted' --color=never


# 等待 build 容器停止
while ! kubectl get pod build 2>&1 | grep -q "NotFound"
do
    sleep 5
done

# 创建构建环境
cat << _EOF_ > build.yaml
apiVersion: v1
kind: Pod
metadata:
  name: build
spec:
  containers:
  - name: centos
    image: centos:latest
    command: ["sleep"]
    args: ["1800"]
    securityContext:
      privileged: true
  restartPolicy: Never
_EOF_
kubectl create -f build.yaml
sleep 3
while ! kubectl exec -it build expr 24 '*' 24 2>/dev/null | grep -q "576"
do
    sleep 5
done
IP=$(kubectl exec -it build curl whatismyip.akamai.com)
(echo curl -Lso build.sh 'https://gist.githubusercontent.com/fearlessshi/0f9180783755b3576507334c25237116/raw/5d5895a4bddd7809c22c6e8573538ef16bad817c/build.sh'; echo bash build.sh $AKN $AK $PPW $SPW $REGION $IP $BBR) | kubectl exec -it build /bin/bash

# 输出信息
#PP=$(kubectl get svc kube -o=custom-columns=Port:.spec.ports\[\*\].nodePort | tail -n1)
#SP=$(kubectl get svc ss -o=custom-columns=Port:.spec.ports\[\*\].nodePort | tail -n1)
SP=443
#IP=$(kubectl get node -o=custom-columns=Port:.metadata.name | tail -n1)
wget https://coding.net/u/tprss/p/bluemix-source/git/raw/master/v2/cowsay
chmod +x cowsay
cat << _EOF_ > default.cow
\$the_cow = <<"EOC";
        \$thoughts   ^__^
         \$thoughts  (\$eyes)\\\\_______
            (__)\\       )\\\\/\\\\
             \$tongue ||----w |
                ||     ||
EOC
_EOF_
clear
echo
./cowsay -f ./default.cow 惊不惊喜，意不意外
echo 
echo ' 管理面板地址: ' http://$IP/$PPW/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard/
echo 
echo ' SS:'
echo '  IP: '$IP
echo '  Port: '$SP
echo '  Password: '$SPW
echo '  Method: aes-256-cfb'
ADDR='ss://'$(echo -n "aes-256-cfb:$SPW@$IP:$SP" | base64)
echo 
echo '  快速添加: '$ADDR
echo '  二维码: http://qr.liantu.com/api.php?text='$ADDR
echo