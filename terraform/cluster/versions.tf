terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.11.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # AWS認証情報は環境変数から自動的に読み込まれます:
  # - AWS_ACCESS_KEY_ID
  # - AWS_SECRET_ACCESS_KEY
  # - AWS_DEFAULT_REGION (オプション)
}

provider "rhcs" {
  # Red Hat Cloud Services の認証方法:
  #
  # 1. サービスアカウント（RHCS_CLIENT_ID / RHCS_CLIENT_SECRET）
  #    推奨: サービスアカウントのクライアントID/シークレットを環境変数で指定
  #      export RHCS_CLIENT_ID="<client_id>"
  #      export RHCS_CLIENT_SECRET="<client_secret>"
  #
  #    注意: サービスアカウントには一部の操作（MachinePool作成など）で
  #    権限が不足する場合があります。その場合はRHCS_TOKENを使用してください。
  #
  # 2. 一時トークン（RHCS_TOKEN）
  #    一時トークンは rosa login で取得できます:
  #      rosa login --use-auth-code  # または --use-device-code
  #      export RHCS_TOKEN=$(rosa token)
  #
  #    注意: MachinePool作成時など、一部の操作ではRHCS_TOKENが必要な場合があります。
  #    有効期限が短いため、長時間の apply や自動化用途では注意が必要です。
}

