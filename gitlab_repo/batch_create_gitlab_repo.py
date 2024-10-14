"""
1. 根据本地文件夹创建群组
2. 创建远程仓库
3. 备份本地仓库当前remote
4. 创建临时remote，推送，
5. 恢复本地原remote
"""
import os

import gitlab
import git

target_repo = {
    # key 为subgroup的名称
    # val为一个路径数组 扫描每个路径下的git_repo 扫描父目录，当前目录与第一层子目录
    "tmp": ["P:\\projects\\tmp"],
}
target_branchs = ['release', 'develop', 'master', 'test', 'develop-feature']
tmp_remote = "tmp_remote"
gitlab_user = ""
gitlab_token = ""
gitlab_url = ''

print("\n ### start ###")
gl = gitlab.Gitlab(url=gitlab_url, private_token=gitlab_token)
target_group_id = '726'
#   获取父群组 手动在页面创建好
group = gl.groups.get(target_group_id)
#   循环要处理的项目
for k in target_repo:
    #   为项目创建子群组
    if not len([sub_groups for sub_groups in group.subgroups.list(iterator=True) if sub_groups.name == k]):
        gl.groups.create({'name': k, 'path': k, 'parent_id': group.get_id()})
    else:
        # 视情况是否阻断处理
        print("子群组 %s 已存在" % k)
    sub_group = [sub_groups for sub_groups in group.subgroups.list(iterator=True) if sub_groups.name == k][0]
    for repo_path in target_repo[k]:
        repos = []
        try:
            #   获取当前目录及父目录git仓库
            repos.append(git.Repo(repo_path, search_parent_directories=True))
        except git.InvalidGitRepositoryError as err:
            print(f"{repo_path} 获取当前目录及父目录git仓库失败")
        if not len(repos):
            listdir_rlt = os.listdir(repo_path)
            for sub_repo_path in listdir_rlt:
                try:
                    #   获取子目录的仓库
                    repos.append(git.Repo(repo_path + "\\" + sub_repo_path, search_parent_directories=True))
                except git.InvalidGitRepositoryError as err:
                    print(f"%s子目录{sub_repo_path}路径获取仓库失败" % repo_path)
        if not len(repos):
            print(f"{k}: {repo_path} 未在父目录，当前目录与第一层子目录下找到git仓库")
            continue
        for repo in repos:
            repo_name = repo.working_dir[repo.working_dir.rindex("\\") + 1:]
            print(f"开始处理{repo_name}")
            #   创建项目
            if not len([projects for projects in gl.projects.list(iterator=True) if projects.name == repo_name]):
                gl.projects.create({'name': repo_name, 'namespace_id': sub_group.id})
            else:
                print("%s 已存在该项目" % repo_name)
            project = [projects for projects in gl.projects.list(iterator=True) if projects.name == repo_name][0]
            # 切换分支 并 更新代码
            for target_branch in target_branchs:
                try:
                    repo.git.checkout(target_branch, "--")
                except Exception as e:
                    print(f"{target_branch} 切换失败")
                    continue
                print(f"处理分支:{[h for h in repo.heads][0].name}")
                repo.git.pull("-f")
                remote_url = project.http_url_to_repo
                remote_url = (remote_url[0: remote_url.find("//") + 2] +
                              f"{gitlab_user}:{gitlab_token}@" +
                              remote_url[remote_url.index("//") + 2:])
                print(f"{repo_name} 创建临时remote")
                remote = repo.remote().add(name=tmp_remote, url=remote_url, repo=repo)
                print(f"{repo_name} 推送代码")
                for pusrlt in remote.push():
                    print(pusrlt)
                print(f"{repo_name} 删除临时remote")
                repo.delete_remote(remote)
                print(f"star {repo_name}")


