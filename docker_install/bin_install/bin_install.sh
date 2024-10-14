## [docker二进制文件下载](https://download.docker.com/linux/static/stable/x86_64/)
# 在页面选择版本下载
curr_dir=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)

##   dockerd docker
cp ${curr_dir}/dockerd /usr/bin/dockerd
cp ${curr_dir}/docker /usr/bin/docker
chmod +x /usr/bin/dockerd /usr/bin/docker
mkdir -p /usr/libexec/docker/cli-plugins
cp ${curr_dir}/docker-init /usr/libexec/docker
# docker-compose 插件 二进制文件对应上面版本下载
#cp -r ${curr_dir}/docker-compose /usr/libexec/docker/cli-plugins
chmod +x /usr/libexec/docker/docker-init /usr/libexec/docker/cli-plugins/*
#  创建配置文件
mkdir -p /etc/docker/
cp ${curr_dir}/daemon.json /etc/docker/daemon.json

# 创建docker用户组
groupadd docker

if [ -x "$(which systemctl)" ]
then
  #  systemd 配置
  echo 'systemd start'
  cp ${curr_dir}/docker.service /etc/systemd/system/docker.service
  systemctl daemon-reload
  systemctl enable --now docker
else
  #  init.d 配置
  echo 'init.d start'
  cp docker /etc/init.d/docker
  service docker start
fi

# 命令自动补全
mkdir -p /usr/share/bash-completion/completions/
cp ${curr_dir}/bash_complete /usr/share/bash-completion/completions/docker

