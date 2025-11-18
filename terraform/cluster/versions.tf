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
  # サービスアカウント（RHCS_CLIENT_ID / RHCS_CLIENT_SECRET）
  # 推奨: サービスアカウントのクライアントID/シークレットを環境変数で指定
  #   export RHCS_CLIENT_ID="<client_id>"
  #   export RHCS_CLIENT_SECRET="<client_secret>"
}

