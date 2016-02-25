#!/bin/bash

# 安装依赖

sudo apt-get update 
sudo apt-get install docker.io wget -y 

wget -O cf.deb 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/cf-cli-installer_6.16.0_x86-64.deb' 
sudo dpkg -i cf.deb 

cf install-plugin -f https://coding.net/u/tprss/p/bluemix-source/git/raw/master/ibm-containers-linux_x64 

# 初始化环境
cf login -a https://api.ng.bluemix.net
cf ic init 

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
CMD ["ssserver","-p","443","-k","${passwd}","-m","aes-256-cfb"]
_EOF_

cf ic build -t ss:v1 . 

# 运行容器
cf ic run --name=ss -p 443 registry.ng.bluemix.net/`cf ic namespace get`/ss:v1

# 显示信息
sleep 30
clear
echo -e "password:\n"${passwd}"\nIP:"
cf ic inspect ss | grep PublicIpAddress | awk -F\" '{print $4}'