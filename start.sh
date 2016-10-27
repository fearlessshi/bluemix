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
sudo apt-get install docker.io wget fortune cowsay -y 

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
sleep 3
cf target -o $org
bx iam space-create dev
sleep 3
cf target -s dev
cf ic namespace set $(openssl rand -base64 8 | md5sum | head -c8)
sleep 3
cf ic init

# 生成密码
passwd=$(openssl rand -base64 8 | md5sum | head -c12)

# 创建镜像
mkdir ss
cd ss

wget -O kcptun.tar.gz 'https://coding.net/u/tprss/p/bluemix-source/git/raw/master/kcptun-linux-amd64-20161025.tar.gz'
tar -zxf kcptun.tar.gz

cat << _EOF2_ > supervisor.sh

#!/bin/bash
easy_install supervisor
mkdir /etc/supervisord.d
echo_supervisord_conf > /etc/supervisord.conf
echo '[include]' >> /etc/supervisord.conf
echo 'files = supervisord.d/*.ini' >> /etc/supervisord.conf

cat << _EOF_ >"/etc/supervisord.d/shadowsocks.ini"
[program:shadowsocks]
command=/usr/bin/ssserver -p 443 -k ${passwd} -m aes-256-cfb
autorestart = true
_EOF_

cat << _EOF_ >"/etc/supervisord.d/kcptun.ini"
[program:kcptun]
command=/usr/local/bin/server_linux_amd64 -l 127.0.0.1:29000 -t 127.0.0.1:443
autorestart = true
_EOF_

cat << _EOF_ >"/etc/supervisord.d/socat.ini"
[program:socat]
command=/usr/bin/socat UDP4-LISTEN:3306,reuseaddr,fork,su=nobody UDP4:127.0.0.1:29000
autorestart = true
_EOF_

_EOF2_


cat << _EOF_ >Dockerfile
FROM centos:centos7
RUN yum install python-setuptools socat -y
RUN easy_install pip
RUN pip install shadowsocks
ADD server_linux_amd64 /usr/local/bin/server_linux_amd64
RUN chmod +x /usr/local/bin/server_linux_amd64
ADD supervisor.sh /tmp/supervisor.sh
RUN bash /tmp/supervisor.sh
EXPOSE 443
EXPOSE 443/udp
EXPOSE 3306/udp
CMD ["supervisord", "-nc", "/etc/supervisord.conf"]
_EOF_

cf ic build -t ss:v1 . 

# 运行容器
cf ic ip bind $(cf ic ip request | cut -d \" -f 2 | tail -1) $(cf ic run -m 1024 --name=ss -p 443 -p 443/udp -p 3306/udp registry.ng.bluemix.net/`cf ic namespace get`/ss:v1)

# 显示信息
while ! cf ic inspect ss | grep PublicIpAddress | awk -F\" '{print $4}' | grep -q .
do
	echo -e "\n"
	curl https://api.lwl12.com/hitokoto/main/get
	sleep 5
done
clear
echo $(echo -e "IP:"
cf ic inspect ss | grep PublicIpAddress | awk -F\" '{print $4}'
echo -e "\nPassword:\n"${passwd}"\nPort:\n443\nMethod:\nAES-256-CFB") | /usr/games/cowsay -n
