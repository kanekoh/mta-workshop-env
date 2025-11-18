# 現在の AWS アカウント ID
data "aws_caller_identity" "current" {}

# ROSA HCP モジュール
module "rosa_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs"
  version = "~> 1.7"

  # --- 必須パラメータ ---
  cluster_name      = var.cluster_name
  openshift_version = var.ocp_version
  machine_cidr      = var.vpc_cidr

  # ネットワークモジュールから取得したSubnet IDを渡す
  aws_subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)

  # ネットワークモジュールから取得したAZを利用
  aws_availability_zones = var.availability_zones

  # --- Compute 設定 ---
  replicas             = var.rosa_replicas
  compute_machine_type = var.rosa_machine_type

  # --- STS / IAM / OIDC 周り ---
  create_account_roles  = true
  account_role_prefix   = "${var.cluster_name}-account"

  create_oidc = true # OIDC Config をモジュールに作らせる

  create_operator_roles = true
  operator_role_prefix  = "${var.cluster_name}-operator-roles"

  # 請求アカウント ID (指定があればそれを優先)
  aws_billing_account_id = var.billing_account != "" ? var.billing_account : data.aws_caller_identity.current.account_id

  # 任意プロパティ
  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  # --- Admin ユーザ作成 ---
  create_admin_user = var.create_admin_user
  
  cluster_admin_username = var.cluster_admin_username
  cluster_admin_password = var.cluster_admin_password

  # クラスター作成の待機を無効化（IDP作成を並行して実行するため）
  wait_for_create_complete            = false
  wait_for_std_compute_nodes_complete = false
}

# HTPasswd IDP for admin + workshop users
resource "rhcs_identity_provider" "workshop_htpasswd" {
  # admin / workshop 両方のパスワードが設定されているときだけ作成
  count = (
    var.admin_password != null && var.admin_password != "" &&
    var.workshop_user_password != null && var.workshop_user_password != ""
  ) ? 1 : 0

  cluster = local.cluster_id
  name    = "workshop-htpasswd"

  htpasswd = {
    users = concat(
      [
        for username in local.admin_usernames : {
          username = username
          password = var.admin_password
        }
      ],
      [
        for username in local.workshop_usernames : {
          username = username
          password = var.workshop_user_password
        }
      ]
    )
  }

  depends_on = [module.rosa_hcp]
}

# HTPasswd IDP for developer user
resource "rhcs_identity_provider" "developer_htpasswd" {
  count = var.developer_password != null && var.developer_password != "" ? 1 : 0

  cluster = local.cluster_id
  name    = "developer-htpasswd"
  htpasswd = {
    users = [
      {
        username = local.developer_username
        password = var.developer_password
      }
    ]
  }

  depends_on = [module.rosa_hcp]
}

