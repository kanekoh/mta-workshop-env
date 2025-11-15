locals {
  cluster_id  = module.rosa_hcp.cluster_id
  admin_group = "cluster-admins"

  # 管理者ユーザー名: admin / admin2 / admin3 ...
  admin_usernames = var.admin_count == 1 ? [
    "admin"
  ] : concat(
    ["admin"],
    [for i in range(2, var.admin_count + 1) : "admin${i}"]
  )

  developer_username = "developer"

  # ワークショップユーザー名: user1 .. userN
  workshop_usernames = [
    for i in range(1, var.workshop_user_count + 1) : "user${i}"
  ]
}

