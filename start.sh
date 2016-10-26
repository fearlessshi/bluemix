#!/bin/bash

# 修正 Coding 的 Ubuntu 源错误
echo 'deb http://au.archive.ubuntu.com/ubuntu/ wily main restricted' | sudo tee /etc/apt/sources.list
echo 'deb http://au.archive.ubuntu.com/ubuntu/ wily-updates main restricted' | sudo tee -a /etc/apt/sources.list
sudo apt-get update
sudo apt-get install --only-upgrade apt -y
cat << _EOF_ | sudo tee /etc/apt/sources.list
deb http://mirrors.163.com/ubuntu/ wily main restricted universe multiverse
deb http://mirrors.163.com/ubuntu/ wily-security main restricted universe multiverse
deb http://mirrors.163.com/ubuntu/ wily-updates main restricted universe multiverse
deb http://mirrors.163.com/ubuntu/ wily-proposed main restricted universe multiverse
deb http://mirrors.163.com/ubuntu/ wily-backports main restricted universe multiverse
deb-src http://mirrors.163.com/ubuntu/ wily main restricted universe multiverse
deb-src http://mirrors.163.com/ubuntu/ wily-security main restricted universe multiverse
deb-src http://mirrors.163.com/ubuntu/ wily-updates main restricted universe multiverse
deb-src http://mirrors.163.com/ubuntu/ wily-proposed main restricted universe multiverse
deb-src http://mirrors.163.com/ubuntu/ wily-backports main restricted universe multiverse
_EOF_
sudo apt-get update

# 安装依赖
sudo apt-get install docker.io wget -y 

wget -O cf.deb 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/cf-cli-installer_6.16.0_x86-64.deb' 
sudo dpkg -i cf.deb 

cf install-plugin -f https://coding.net/u/tprss/p/bluemix-source/git/raw/master/ibm-containers-linux_x64

wget 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/Bluemix_CLI_0.4.3_amd64.tar.gz'
tar -zxf Bluemix_CLI_0.4.3_amd64.tar.gz
cd Bluemix_CLI
sudo ./install_bluemix_cli
cd ..

# 初始化环境
org=$(openssl rand -base64 8 | md5sum | head -c8)
cf login -a https://api.ng.bluemix.net
bx iam org-create $org
cf target -o $org
bx iam space-create dev
cf target -s dev
cf ic namespace set $(openssl rand -base64 8 | md5sum | head -c8)
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
cf ic ip bind $(cf ic ip request | cut -d \" -f 2 | tail -1) $(cf ic run --name=ss -p 443 registry.ng.bluemix.net/`cf ic namespace get`/ss:v1)

# 显示信息
sleep 30
clear
echo -e "password:\n"${passwd}"\nIP:"
cf ic inspect ss | grep PublicIpAddress | awk -F\" '{print $4}'