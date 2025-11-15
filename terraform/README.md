# Terraform Configuration for ROSA

このディレクトリには、Red Hat OpenShift for AWS (ROSA) HCPクラスターを構築するためのTerraform設定が含まれています。

## 環境変数による設定管理

このプロジェクトでは、機密情報を含むすべての主要な設定を環境変数で管理します。

### TF_VAR_* 環境変数

Terraformは `TF_VAR_` プレフィックスを持つ環境変数を自動的に認識します：

```bash
# env.sh で設定
export TF_VAR_aws_region="ap-northeast-1"
export TF_VAR_cluster_name="mta-lightspeed"
export TF_VAR_ocp_version="4.19"
export TF_VAR_billing_account="123456789012"  # 機密情報

# Terraform実行時に自動的に変数として認識される
terraform plan
# → var.aws_region = "ap-northeast-1"
# → var.cluster_name = "mta-lightspeed"
# などと同等
```

### 管理される変数

以下の変数は `env.sh` で環境変数として設定されます：

| 環境変数 | Terraform変数 | 説明 | 機密性 |
|---------|--------------|------|-------|
| `TF_VAR_aws_region` | `var.aws_region` | AWSリージョン | 低 |
| `TF_VAR_cluster_name` | `var.cluster_name` | クラスター名 | 低 |
| `TF_VAR_ocp_version` | `var.ocp_version` | OpenShiftバージョン | 低 |
| `TF_VAR_billing_account` | `var.billing_account` | AWS Billing Account ID | **高** |
| `TF_VAR_rosa_machine_type` | `var.rosa_machine_type` | EC2インスタンスタイプ | 低 |
| `TF_VAR_rosa_replicas` | `var.rosa_replicas` | ノード数 | 低 |
| `TF_VAR_vpc_cidr` | `var.vpc_cidr` | VPC CIDR | 低 |
| `TF_VAR_availability_zone_count` | `var.availability_zone_count` | AZ数 | 低 |

### AWS認証情報

AWS SDKの標準環境変数を使用：

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

## 使用方法

### 基本フロー

```bash
# 1. 環境変数を読み込む
cd /path/to/project
source env.sh

# 2. Terraformディレクトリに移動
cd terraform

# 3. 初期化
terraform init

# 4. 実行計画
terraform plan

# 5. 適用
terraform apply

# 6. 出力確認
terraform output cluster_console_url
terraform output -json ansible_inventory_json
```

### terraform.tfvars の使用（オプション）

環境変数をオーバーライドしたい場合のみ、`terraform.tfvars` を使用：

```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**優先順位**:
1. `terraform.tfvars` で指定した値（最優先）
2. `TF_VAR_*` 環境変数
3. `variables.tf` のデフォルト値

## セキュリティのベストプラクティス

### ✅ 推奨

- ✅ `env.sh` で機密情報を管理
- ✅ `env.sh` を `.gitignore` に追加
- ✅ 環境変数（`TF_VAR_*`）を使用
- ✅ AWS認証情報は標準環境変数を使用

### ❌ 非推奨

- ❌ `terraform.tfvars` に機密情報を記載
- ❌ ソースコードに認証情報をハードコード
- ❌ Gitに機密情報をコミット

## ファイル構成

```
terraform/
├── versions.tf              # プロバイダー設定
├── variables.tf             # 変数定義
├── network.tf               # VPC/ネットワーク
├── main.tf                  # ROSAクラスター
├── outputs.tf               # 出力定義
├── terraform.tfvars.example # 設定サンプル
└── README.md               # このファイル
```

## トラブルシューティング

### 環境変数が認識されない

```bash
# 環境変数の確認
env | grep TF_VAR_

# 再読み込み
source ../env.sh
```

### 変数の優先順位を確認

```bash
# Terraform Consoleで確認
terraform console
> var.cluster_name
> var.ocp_version
```

### デバッグモード

```bash
export TF_LOG=DEBUG
terraform plan
```

## 参考リンク

- [Terraform Environment Variables](https://www.terraform.io/language/values/variables#environment-variables)
- [ROSA Documentation](https://docs.openshift.com/rosa/)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)

