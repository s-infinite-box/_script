## [docker二进制文件下载](https://download.docker.com/linux/static/stable/x86_64/)
##   dockerd docker
if [ -z $p_dir ]
then
  . /etc/profile
fi

if [ -z $p_dir ];then
  p_dir=/root/p
  echo "p_dir set $p_dir"
fi

if [ -z $linux_data ];then
  linux_data=/root/p/linux-app
  echo "linux_data set $linux_data"
fi
cp ${linux_data}/apps/docker/dockerd /usr/bin/dockerd
cp ${linux_data}/apps/docker/docker /usr/bin/docker
chmod +x /usr/bin/dockerd /usr/bin/docker
#   插件
mkdir -p /usr/libexec/docker
cp -r ${linux_data}/apps/docker/cli-plugins/ ${linux_data}/apps/docker/docker-init /usr/libexec/docker
chmod +x /usr/libexec/docker/docker-init /usr/libexec/docker/cli-plugins/*
#  创建配置文件
mkdir -p /etc/docker/
cp $p_dir/pphome/docker/install/bin_install/daemon.json /etc/docker/daemon.json

# 创建docker用户组
groupadd docker

if [ -x "$(which systemctl)" ]
then
  #  systemd 配置
  #cp $p_dir/pphome/docker/install/bin_install/docker.socket /etc/systemd/system/docker.socket
  echo 'systemd start'
  cp $p_dir/pphome/docker/install/bin_install/docker.service /etc/systemd/system/docker.service
  systemctl daemon-reload
  systemctl enable --now docker
else
  #  init.d 配置
  echo 'init.d start'
  cp $p_dir/pphome/docker/install/bin_install/docker /etc/init.d/docker
  service docker start
fi

# 命令自动补全
mkdir -p /usr/share/bash-completion/completions/
cp $p_dir/pphome/docker/install/bin_install/bash_complete /usr/share/bash-completion/completions/docker

