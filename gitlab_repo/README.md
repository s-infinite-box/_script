### gitlab的一些运维脚本

#### 背景：

    之前公司有一些任务需要转移仓库之类的，一个个手动操作很麻烦还容易出错，就查看了gitlab的api和SDK写了这些脚本

#### 列表：

- gitlab_user_to_execl.py， 导出gitlab的用户为execl

- batch_create_gitlab_repo.py 批量到处gitlab仓库到本地

- contrast_branch.py  对比两个gitlab上的仓库分支

- copy_gitlab_group.py  从一个gitlab复制所有仓库到本地，再推送到新gitlab


