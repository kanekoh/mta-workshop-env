# Terraform Configuration for ROSA HCP

ROSA HCP クラスターを構築するための Terraform 設定。
ネットワーク（VPC）とクラスターの 2 つのルートモジュールで構成される。

## ディレクトリ構成

```
terraform/
├── network/                      # VPC / サブネット / NAT
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars.example
└── cluster/                      # ROSA HCP クラスター + IDP + MachinePool
    ├── main.tf                   # rosa-hcp モジュール + HTPasswd IDP
    ├── machinepools.tf           # 追加 MachinePool（extra-workers, GPU 等）
    ├── locals.tf                 # レプリカ数計算、ユーザー名生成、IAM ARN
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    └── terraform.tfvars.example
```

## 設定の階層

```
env.sh          シークレット + AWS アカウント共通設定
  ↓ 上書き
profiles/*.env  クラスター構成（サイズ、バージョン、GPU、GitOps 環境）
  ↓ 上書き
deploy.sh       CLI フラグ + auto.tfvars 自動生成
  ↓
terraform apply
```

### 変数の優先順位

1. `terraform.tfvars` / `*.auto.tfvars`（最優先）
2. `TF_VAR_*` 環境変数（`env.sh` + `profiles/*.env`）
3. `variables.tf` のデフォルト値

## 使用方法

通常は `deploy.sh` 経由で実行する:

```bash
source env.sh
export PROFILE=ai-serving    # profiles/ai-serving.env
./deploy.sh
```

`deploy.sh` が以下を自動処理する:

1. `terraform/network` を apply → VPC / サブネット作成
2. network の出力を `cluster/network-outputs.auto.tfvars` に書き出し
3. プロファイルの GPU/ODF 設定を `cluster/additional-pools.auto.tfvars` に書き出し
4. `terraform/cluster` を apply → ROSA HCP 作成
5. クラスター情報を `ansible/cluster_info.json` に出力

### 手動実行

```bash
source env.sh

cd terraform/network
terraform init && terraform apply

cd ../cluster
terraform init && terraform apply
```

手動実行時は `network-outputs.auto.tfvars` を自分で作成する必要がある。

## 主要な変数

### env.sh で設定（シークレット・共通）

| 環境変数 | 説明 |
|---------|------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | AWS 認証 |
| `RHCS_CLIENT_ID` / `RHCS_CLIENT_SECRET` | RHCS プロバイダ認証 |
| `TF_VAR_aws_region` | AWS リージョン |
| `TF_VAR_vpc_cidr` | VPC CIDR |
| `TF_VAR_billing_account` | AWS Billing Account ID |
| `TF_VAR_ocp_version` | OpenShift バージョン（デフォルト値なし・必須） |
| `TF_VAR_admin_password` / `TF_VAR_cluster_admin_password` | パスワード |

### profiles/*.env で設定（クラスター構成）

| 変数 | 説明 |
|------|------|
| `TF_VAR_cluster_name` | クラスター名（CLUSTER_NAME_PREFIX が前置される） |
| `TF_VAR_ocp_version` | OpenShift バージョン（env.sh を上書き） |
| `TF_VAR_rosa_machine_type` | ワーカーのインスタンスタイプ |
| `TF_VAR_worker_pool_replicas` | 追加 Worker 数（0=初期プールのみ） |
| `TF_VAR_availability_zone_count` | AZ 数（1 or 3） |
| `GPU_MACHINE_TYPE` / `GPU_REPLICAS` | GPU ノード設定（deploy.sh が auto.tfvars に変換） |

## MachinePool 戦略

| プール | 管理元 | 備考 |
|--------|--------|------|
| 1st（初期） | `rosa-hcp` モジュール | Single-AZ=2, Multi-AZ=3。作成後変更不可 |
| 2nd `extra-workers` | `machinepools.tf` | `worker_pool_replicas > 0` で作成 |
| 3rd+ `additional` | `machinepools.tf` | GPU/ODF 等。deploy.sh が auto.tfvars を生成 |

## 使用モジュール・プロバイダ

| コンポーネント | ソース | バージョン |
|---------------|--------|-----------|
| rosa-hcp モジュール | `terraform-redhat/rosa-hcp/rhcs` | `~> 1.7.4` |
| RHCS プロバイダ | `terraform-redhat/rhcs` | `>= 1.7.7` |
| AWS プロバイダ | `hashicorp/aws` | `>= 6.51.0` |

## セキュリティ

- `env.sh` は `.gitignore` に登録済み。Git にコミットしない
- `terraform.tfvars` も `.gitignore` 対象
- `*.auto.tfvars` は `deploy.sh` が生成。機密情報は含まない
- Gitleaks のカスタムルールで Terraform 変数内のシークレットを検出する設定済み
