#!/bin/bash

# 安装依赖

echo -e '开始安装docker。。。'
sudo apt-get update >/dev/null 2>&1
sudo apt-get install docker.io wget -y >/dev/null 2>&1
echo -e '完毕\n'

echo -e '开始安装cf命令。。。'
wget -O cf.deb 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/cf-cli-installer_6.16.0_x86-64.deb' >/dev/null 2>&1
sudo dpkg -i cf.deb >/dev/null 2>&1
echo -e '完毕\n'

echo -e '开始安装ic插件。。。'
cf install-plugin -f https://coding.net/u/tprss/p/bluemix-source/git/raw/master/ibm-containers-linux_x64 >/dev/null 2>&1
echo -e '完毕\n'

# 初始化环境
clear
echo -e '登陆Bluemix账户中。。。\n'
cf login -a https://api.ng.bluemix.net
cf ic init >/dev/null 2>&1
clear

# 生成密码
passwd=`openssl rand -base64 12`

# 创建镜像
mkdir ss
cd ss

cat << _EOF_ >Dockerfile
FROM centos:centos7
RUN yum install python-setuptools -y
RUN easy_install pip
RUN pip install shadowsocks
EXPOSE 443
CMD ["ssserver","-p","443","-k",${passwd},"-m","aes-256-cfb"]
_EOF_

echo -e '开始构建镜像。。。'
cf ic build -t ss:v1 . >/dev/null 2>&1
echo -e '完毕\n'

# 运行容器
echo -e '创建SS容器。。。'
cf ic run --name=ss -p 443 registry.ng.bluemix.net/`cf ic namespace get`/ss:v1
echo -e '完毕\n'

# 显示信息
echo '容器启动中。。。'
sleep 15
clear
echo -e "password:\n"${passwd}"\naddress:"
cf ic inspect ss | grep HostIp | awk -F\" '{print $4}'