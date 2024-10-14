import _thread
import os
import threading
import time

"""
pip install python-gitlab
pip install gitdb
"""
import gitlab
import git

#   目标gitlab的父群组名称
target_gitlab_parent_group_name = 'finshine'
#   目标gitlab的父群组描述
target_gitlab_parent_group_description = "上汽帆一项目，金桥团队维护"
#   要同步的分支，有则同步无则跳过
target_branchs = ['release', 'develop', 'master', 'test', 'develop-feature', 'BOC3.3_release']
#   要同步的群组 为空则同步所有
copy_group = []
#   创建的临时remote
tmp_remote = "tmp_remote"
#   本地存储git仓库的目录
local_repo_dir = 'q:\\repo_back'
#   并行处理最大线程
task_count_limit = 16

target_gitlab_user = ""
target_gitlab_token = ""
target_gitlab_url = ''

source_gitlab_user = ""
source_gitlab_token = ""
source_gitlab_url = ''

#   只更新本地
only_updated_local = True
print("\n ### start ###")
print(f"处理目标gitlab父群组{target_gitlab_parent_group_name}")
#   模板gitlab操作对象
target_gl = gitlab.Gitlab(url=target_gitlab_url, private_token=target_gitlab_token, keep_base_url=True)
if not only_updated_local and not [tg for tg in target_gl.groups.list(keep_base_url=True, iterator=True)
                                   if tg.name == target_gitlab_parent_group_name]:
    print(f"创建target_gitlab父群组{target_gitlab_parent_group_name}")
    target_gl.groups.create({'name': target_gitlab_parent_group_name,
                             'path': target_gitlab_parent_group_name,
                             'description': target_gitlab_parent_group_description})
target_gitlab_parent_group = [tg for tg in target_gl.groups.list(keep_base_url=True, iterator=True)
                              if tg.name == target_gitlab_parent_group_name][0]
#   源gitlab操作对象
source_gl = gitlab.Gitlab(url=source_gitlab_url, private_token=source_gitlab_token)
source_groups = source_gl.groups.list(keep_base_url=True, iterator=True)
fail_repo = []
#   当前正在处理的任务数量
task_count = 0
#   线程锁对象
lock = threading.RLock()

rlt = {}


#   仓库处理函数 便于线程处理
def process(source_project_arg, tsg_arg, source_group_arg):
    """
    处理源项目，克隆并推送至目标仓库。

    参数:
    source_project_arg: 源项目参数对象，包含项目名和克隆URL。
    tsg_arg: 目标组参数对象，用于创建目标项目。
    source_group_arg: 源组参数对象，用于记录源组信息。

    返回:
    无
    """
    # 获取源项目名称和构建克隆URL
    repo_name = source_project_arg.name
    repo_path = local_repo_dir + os.sep + source_group.name + os.sep + repo_name
    try:
        print(f"开始处理project: {repo_name}")
        clone_url = (source_project_arg.http_url_to_repo[0: source_project_arg.http_url_to_repo.find("//") + 2] +
                     f"{source_gitlab_user}:{source_gitlab_token}@" +
                     source_project_arg.http_url_to_repo[source_project_arg.http_url_to_repo.index("//") + 2:])
        if not os.path.exists(repo_path):
            print(f"克隆项目{repo_path}")
            git.Repo.clone_from(url=clone_url, to_path=repo_path)
        print(f"创建项目{repo_name}")
        if not only_updated_local and not len(
                [projects for projects in target_gl.projects.list(iterator=True) if projects.name == repo_name]):
            target_gl.projects.create({'name': repo_name,
                                       'namespace_id': tsg_arg.id,
                                       'description': source_project_arg.description, })
        else:
            print("%s 已存在该项目" % repo_name)
        project = None
        if not only_updated_local:
            project = [projects for projects in target_gl.projects.list(iterator=True) if projects.name == repo_name][0]

        print(f"获取{repo_name}的仓库{repo_path}")
        repo = git.Repo(repo_path)
        rlt.setdefault(repo_name, [])
        for target_branch in target_branchs:
            try:
                repo.git.checkout(target_branch, "--")
            except Exception as e:
                print(f"{target_branch} 切换失败: {e}")
                continue
            hd = [h for h in repo.heads][0].name
            print(f"处理分支:{hd}")
            repo.git.pull("-f")
            if only_updated_local:
                continue
            remote_url = project.http_url_to_repo
            remote_url = (remote_url[0: remote_url.find("//") + 2] +
                          f"{target_gitlab_user}:{target_gitlab_token}@" +
                          remote_url[remote_url.index("//") + 2:])
            print(f"{repo_name} 创建临时remote")
            remote = repo.remote().add(name=tmp_remote, url=remote_url, repo=repo)
            print(f"{repo_name} 推送代码")
            remote.push()
            print(f"{repo_name} 删除临时remote")
            repo.delete_remote(remote)
            print(f"{repo_name} end")
            rlt.get(repo_name).append(hd)
    except git.InvalidGitRepositoryError as err:
        print(f"目录{repo_path}路径获取仓库失败: {err}")
        fail_repo.append(
            {"name": repo_name, "source_group": source_group_arg.name, "local_repo_path": repo_path, "err": err})
    except Exception as e:
        print(f"{repo_name}处理失败: {e}")
        fail_repo.append(
            {"name": repo_name, "source_group": source_group_arg.name, "local_repo_path": repo_path, "err": err})
    finally:
        lock.acquire()
        global task_count
        task_count -= 1
        lock.release()


for source_group in source_groups:
    if source_group.name.count("gitops") > 0:
        print(f"跳过gitops项目{source_group.name}")
        continue
    if copy_group.__len__() > 0 and source_group.name not in copy_group:
        continue
    if (not only_updated_local and
            not [tsg for tsg in target_gitlab_parent_group.subgroups.list(iterator=True) if
                 tsg.name == source_group.name]):
        print(f"创建子群组")
        target_gl.groups.create({'name': source_group.name,
                                 'path': source_group.full_path,
                                 'parent_id': target_gitlab_parent_group.id,
                                 'description': source_group.description, })
    #   目标gitlab子群组
    tsg = [tsg for tsg in target_gitlab_parent_group.subgroups.list(iterator=True) if tsg.name == source_group.name][0]
    print(f"开始处理{tsg.id}: {tsg.name}相关项目")
    for source_project in source_group.projects.list(keep_base_url=True, iterator=True):
        sleep_time = 1
        while task_count >= task_count_limit:
            print(f"当前执行任务数{task_count} 等待{sleep_time}秒")
            time.sleep(sleep_time)
        lock.acquire()
        task_count += 1
        lock.release()
        _thread.start_new_thread(process, (source_project, tsg, source_group))
sleep_time = 3
while task_count > 0:
    print(f"当前未完成任务数{task_count} 等待{sleep_time}秒")
    time.sleep(sleep_time)
print(rlt)
print(f"处理失败repo:\n{fail_repo}")
print("### end ###")
