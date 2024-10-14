import pandas as pd
import gitlab

"""
导出gitlab的用户为execl
"""


target_gitlab_token = ""
target_gitlab_url = ''

target_gl = gitlab.Gitlab(url=target_gitlab_url, private_token=target_gitlab_token)
ids = []
name = []
username = []
email = []
status = []
is_admin = []

users = target_gl.users.list(keep_base_url=True, iterator=True)
for u in users:
    ids.append(u.id)
    name.append(u.name)
    username.append(u.username)
    email.append(u.email)
    status.append(u.state)
    is_admin.append(u.is_admin)


df = pd.DataFrame({'id': ids, 'name': name, 'username': username, 'email': email, 'status': status, 'is_admin': is_admin})
df.to_excel('output.xlsx', index=False)
print()
