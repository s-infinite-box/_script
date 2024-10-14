#!/usr/bin/python3
import http.client
import json
import os
import sys
import threading
import time

author = """
## Auth       : songwz
## build      : by python3 on 2023/8/25
## Desc       : 通过ctr命令推送测试环境指定工作负载的镜像到生产环境制品仓
## Last Update: 2024/3/27
"""
print()
#   proc Cookie
proc_cookie = ("")

#   发布的工作负载名称
projects_temp_str = '''
[
    'nfs',
]
'''
projects_str = projects_temp_str
project_images_file_name = 'push-images'
projects = []

def get_projects_str():
    #   若当前路径下有push-image文件,则使用push-image文件中的项目
    if os.path.exists(project_images_file_name) and os.path.isfile(project_images_file_name):
        with open(project_images_file_name, 'r') as f:
            var1 = f.read()
            if var1 is None or var1 == '':
                print("push-image文件内容为空,使用默认项目")
            #   去除前后空格
            var1 = var1.strip()
            #   若文件内容不为空,且以[开头,]结尾,则使用文件中的项目
            if var1 != '' and var1.startswith('[') and var1.endswith(']'):
                global projects_str
                projects_str = var1
            else:
                print("push-image文件内容不正确,请检查文件内容,文件内容必须以'['开头,']'结尾")
                sys.exit("END")


def get_projets():
    eval_rlt = eval(projects_str)
    if type(eval_rlt) is not list:
        print("push-image文件内容不正确,请检查文件内容,文件内容必须为数组")
        sys.exit(1)
    projects.extend(eval_rlt)
    for proj in projects:
        if type(proj) is not str:
            print("%s存在特殊项: %s，请检查" % (project_images_file_name, proj))
            sys.exit(1)


#   推送的镜像
push_image = []
#   报错镜像
err = []
#   跳过的容器
skip_container = []
#   proc预生产所有容器镜像
proc_container_images = []
#   记录处理进度
task_count = 0
#   windows默认线程数
win_worker_count = 5
#   linux默认线程数
linux_worker_count = 15
#   实际线程数
worker_count = win_worker_count
if sys.platform == 'linux':
    worker_count = linux_worker_count
#   最大线程数
worker_count_max = 20
#   线程锁
lock = threading.RLock()
#   记录开始时间
init_time = time.time()
#   镜像缓存
images_cache = []
#   预生产host
proc_host = ""
#   预生产path
proc_uri = ""
#   kuboard登录
KuboardAccessKey = ''
KuboardUsername = ''
kuboard_daemon = ""
#   目标镜像仓库地址
dest_reg_url = 'a.com/a-tenant'
#   源镜像仓库账号密码
src_reg_pass = 'username1:password1'
#   目标镜像仓库账号密码
dest_reg_pass = 'username2:password2'

def get_worker_num():
    current_worker_num = 0
    for _ in threading.enumerate():
        if type(_) == DockerThread:
            current_worker_num += 1
    return current_worker_num


class DockerThread(threading.Thread):
    def __init__(self, img_name, i, num):
        threading.Thread.__init__(self)
        self.img_name = img_name
        self.index = i
        self.num = num
        self.start_time = time.time()
        self.log_str = ''
        #   计数器加1
        lock.acquire()
        global task_count
        task_count += 1
        lock.release()

    def run(self):
        #   镜像处理过程
        img_name = self.img_name
        proc_img_name = ''
        self.log_str = (self.index + 1).__str__() + "/" + self.num.__str__() + '.处理: ' + image + '\n'
        end_flag = False
        try:
            #   修改镜像仓库名称
            proc_img_name = dest_reg_url + img_name[img_name.rfind('/')::]
            #   如果proc已存在此镜像则不做处理
            if proc_container_images.count(proc_img_name[proc_img_name.find('/')::]) > 0:
                self.log_str += ("\t已存在当前proc仓库,不做处理,镜像名 : " + img_name) + '\n'
                return

            #   拉取镜像 -u 指定用户名密码 -k 跳过证书验证
            cmd = f'ctr i pull -k -u {src_reg_pass} ' + img_name
            self.log_str += ('\t拉取镜像: ' + cmd) + '\n'
            os.system(cmd)

            #   修改镜像仓库名称
            cmd = 'ctr i tag ' + img_name + " " + proc_img_name
            self.log_str += ('\t修改镜像仓库名称: ' + cmd) + '\n'
            os.system(cmd)

            #   推送镜像
            cmd = f'ctr i push -k -u {dest_reg_pass} ' + proc_img_name
            self.log_str += ('\t推送镜像: ' + cmd) + '\n'
            os.system(cmd)

            end = time.time()
            lstr = "\t处理结束,耗时 %s 秒" % int(end - self.start_time) + '\n'
            if end - self.start_time > 60:
                lstr += " , 耗时超过1分钟###################"
            self.log_str += lstr + '\n'
            end_flag = True
        except Exception as ex:
            self.log_str += ('\t处理错误,镜像: \n\t' + img_name + ':') + '\n\t'
            self.log_str += ex.__str__()
            err.append(img_name + "\n\t" + proc_img_name + '\n\t' + ex.__str__() + '\n\t')
        finally:
            print(self.log_str)
            #   计数器减1
            lock.acquire()
            global task_count
            task_count -= 1
            #   记录镜像
            if end_flag:
                push_image.append(proc_img_name)
                images_cache.append(img_name)
            lock.release()


if __name__ == '__main__':
    args = sys.argv[1:]

    if len(args) == 1:
        if args[0] == '-h' or args[0] == '--help':
            print('''
push-release-image-multithreading-by-ctr [option] "proc_cookie"

proc_cookie:          proc登录cookie,可在浏览器中获取,登录proc后按F12,在Network中找到请求头中的Cookie,复制即可,
                     注意前后添加双引号("")号，避免cookie中有空格导致参数错误
                
option:
    -h, --help       显示该帮助
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
    
''' % (linux_worker_count, project_images_file_name, project_images_file_name))
            sys.exit("%s" % author)
        if args[0] == '-f' or args[0] == '--file':
            print('## 处理服务:\n' + projects_temp_str)
            sys.exit(author)
        get_projects_str()
        get_projets()
        if args[0] == '-p' or args[0] == '--projects':
            print('## 处理服务:\n' + projects_str)
            sys.exit(author)
        proc_cookie = args[0]
    if len(args) > 1:
        #   多参数目前仅支持指定线程数
        (args[0] != '-w' and args[0] != '--worker') and (print("参数错误,请检查参数是否正确") or sys.exit(1))
        worker_count = int(args[1])
        #   限制线程数范围
        if worker_count > worker_count_max or worker_count < 1:
            print("线程数必须在1-%s之间" % worker_count_max.__str__())
            sys.exit(1)
        get_projects_str()
        get_projets()
        proc_cookie = args[2]
    # while True:
    print("@@@@@@@@@\t开始处理\t@@@@@@@@@\n")
    #  检查ctr命令是否存在
    output = os.popen("which ctr")
    check_ctr_rlt = output.buffer.read().decode('utf-8')
    if check_ctr_rlt == '':
        print("请先安装ctr命令，查看containerd.io安装是否成功")
        sys.exit(1)

    #   proc生产所有容器镜像
    proc_container_images = []
    conn = http.client.HTTPSConnection(proc_host)
    conn.request("GET", proc_uri, headers={"Cookie": proc_cookie})
    proc_reps = conn.getresponse()
    if proc_reps.__getattribute__('code') != 200:
        print("请求proc失败,请检查cookie是否正确")
        sys.exit(1)
    proc_pods = []
    try:
        proc_pods = json.loads(proc_reps.read().decode("utf-8")).get("data")
    except JSONDecodeError as e:
        print("解析proc数据失败")
        print(e)
        sys.exit(1)
    if len(proc_pods) == 0:
        print("proc获取容器失败")
        sys.exit(1)
    for pod in proc_pods:
        for container in pod.get("containers"):
            proc_container_images.append(container.get("image")[container.get("image").find('/')::])
    print("proc容器镜像获取完成,共 " + len(
        proc_container_images).__str__() + " 个, " + proc_container_images.__str__() + "\n")
    #   测试环境kuboard请求
    conn = http.client.HTTPConnection(kuboard_daemon)
    headers = {
        'Cookie': f"KuboardUsername={KuboardUsername}; KuboardAccessKey={KuboardAccessKey}",
    }
    #   请求kuboard获取负载数据
    kuboard_uri = "/k8s-api/AA-test/apis/apps/v1/namespaces/aik3-test/deployments"
    conn.request("GET", kuboard_uri, headers=headers)
    kuboard_reps = conn.getresponse()
    if kuboard_reps.getcode() != 200:
        print("请求kuboard失败 请检查kuboard访问密钥%s" % KuboardAccessKey)
        print("返回body %s" % kuboard_reps.read())
        sys.exit(1)
    items = []
    try:
        items = json.loads(kuboard_reps.read()).get('items')
    except JSONDecodeError as e:
        print("kuboard请求成功, 但解析kuboard数据为json失败, body: %s" % kuboard_reps.read().decode("utf-8"))
        print(e)
        sys.exit(1)
    if len(items) == 0:
        print("kuboard获取deployments数量为0, url: %s" % (kuboard_daemon + kuboard_uri))
        sys.exit(1)
    print("kuboard负载获取完成,共 " + len(items).__str__() + " 个\n")

    print("开始处理镜像\n")
    for index in range(len(items)):
        item = items[index]
        #   获取负载中的容器
        if item['metadata']['name'] not in projects:
            continue
        containers = item['spec']['template']['spec']['containers']
        for container in containers:
            #   镜像名称
            image = container['image']
            #   项目名称
            name = image[image.rfind('/') + 1:image.rfind(':'):]
            while get_worker_num() >= worker_count:
                time.sleep(1)
            thread = DockerThread(image, i=index + 1, num=len(items))
            thread.start()

    print("\n\n")
    while task_count > 0:
        for e in threading.enumerate():
            if type(e) == DockerThread:
                print("\n正在处理: " + e.__getattribute__('img_name') + "")
                print("当前用时: %s 秒" % int(time.time() - e.__getattribute__('start_time')))
                print("处理进度: \n" + e.__getattribute__('log_str'))
        print("剩余执行任务数:" + str(task_count) + "个")
        print("##################################################\n\n\n")
        time.sleep(5)

    print("清理镜像缓存: ")
    images_cache.extend(push_image)
    #   拼装清理命令
    ctr_clean_images_cache_cmd = "ctr i rm"
    for e in images_cache:
        ctr_clean_images_cache_cmd += " " + e
    os.system(ctr_clean_images_cache_cmd)
    print("\n当前容器镜像:")

    os.system("ctr i ls")
    print("\n")

    print("跳过容器:")
    for var in skip_container:
        print('\t' + var)
    print("推送镜像")
    for var in push_image:
        print("\t" + var)
    err.__len__() > 0 and print("报错!!")
    for var in err:
        print("\t" + var)
    print("处理结束, 总计耗时 %s 秒\n\n##################################################\n\n\n" % int(
        time.time() - init_time))


