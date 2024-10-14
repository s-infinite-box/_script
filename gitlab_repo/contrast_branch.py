import gitlab

target_gitlab_user = ""
target_gitlab_token = ""
target_gitlab_url = ''

source_gitlab_user = ""
source_gitlab_token = ""
source_gitlab_url = ''
target_gitlab_parent_group_name = 'finshine'
target_branchs = ['release', 'develop', 'master', 'test', 'develop-feature', 'BOC3.3_release']

target_gl = gitlab.Gitlab(url=target_gitlab_url, private_token=target_gitlab_token)
target_gitlab_parent_group = [tg for tg in target_gl.groups.list(keep_base_url=True, iterator=True)
                              if tg.name == target_gitlab_parent_group_name][0]
source_gl = gitlab.Gitlab(url=source_gitlab_url, private_token=source_gitlab_token)
tsgs = target_gitlab_parent_group.subgroups.list(keep_base_url=True, iterator=True)
sgs = source_gl.groups.list(keep_base_url=True, iterator=True)

rlt = {}
for sg in sgs:
    sps = sg.projects.list(keep_base_url=True, iterator=True)
    for sp in sps:
        tp = target_gl.projects.list(search=sp.name)
        if not len(tp):
            print('not found', sp.name)
            continue
        tp = tp[0]

        print()
