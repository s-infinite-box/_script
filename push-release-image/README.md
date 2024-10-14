# 说明
python3编写的脚本，用于批量推送镜像到k8s集群，支持多线程并发推送；
使用ctr 命令推送镜像，从kuboard上获取镜像名称拉取到本地再推送到集群；
可以单独将DockerThread类拷走，只作为推送工具使用。
# 使用
```
push-release-image-multithreading-by-ctr [option] "proc_cookie"
option:
    -h, --help       显示帮助
    -p, --projects   显示当前欲处理的项目 
    -f, --file       输出项目配置文件模板
    -w, --worker     指定线程数,linux默认%s线程
example:
    python3 push-release-image-multithreading.py "proc_cookie"
    python3 push-release-image-multithreading.py -w 5 "proc_cookie"
    python3 push-release-image-multithreading.py -p
    python3 push-release-image-multithreading.py -h

项目配置:
    项目优先从脚本执行目录下的\"%s\"文件中获取，可通过 -f 参数生成模板内容保存到文件中
    若文件不存在或文件为空，则使用脚本中的默认项目
    项目名为测试环境kuboard中的工作负载（deployment）的名称
    
\"%s\"格式:
    格式本质为python数组,与json格式基本一致
    数组元素须为字符串
    支持#注释（行注释）以及其他python注释
    example: 
        [ "project1", "project2", "project3" ]
        [
            # comment 
            "project1", 
            "project2" 
        ]
    
```