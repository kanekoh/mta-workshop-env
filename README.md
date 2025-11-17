# MTA for Developer Lightspeed ワークショップ環境構築

このリポジトリは、MTA for Developer Lightspeedワークショップのための環境を自動構築するためのTerraform、Ansible、GitOps設定を含んでいます。

## 概要

- **Terraform**: Red Hat OpenShift for AWS (ROSA) HCP クラスターの構築
- **Ansible**: OpenShift IDP設定、ArgoCD構築などの構成管理
- **GitOps**: 継続的デリバリーとアプリケーションデプロイ

## 前提条件

### 必要なツール

1. **Terraform** (>= 1.5.0)
   ```bash
   brew install terraform
   ```

2. **AWS CLI** (>= 2.0)
   ```bash
   brew install awscli
   ```

3. **ROSA CLI**
   ```bash
   brew install rosa-cli
   ```

4. **Ansible** (>= 2.14) - 後続のステップで使用
   ```bash
   brew install ansible
   ```

5. **OpenShift CLI (oc)**
   ```bash
   brew install openshift-cli
   ```

### 必要な認証情報

1. **AWS認証情報**
   - AWS Access Key ID
   - AWS Secret Access Key
   - 適切な権限（EC2、VPC、IAM等）

2. **Red Hat Cloud Services 認証**
   
   ROSAにログインするには2つの方法があります：
   
   **オプション1 (ブラウザ環境の場合):**
   ```bash
   rosa login --use-auth-code
   ```
   
   **オプション2 (ブラウザレス環境の場合):**
   ```bash
   rosa login --use-device-code
   ```
   
   ブラウザウィンドウでRed Hatのログイン認証情報をSSOで入力してください。
   
   **Terraformプロバイダー用の認証:**
   
   TerraformのRHCSプロバイダーは、以下の2つの認証方法をサポートしています：
   
   **方法1: サービスアカウント（推奨、ただし一部操作で権限不足の可能性あり）**
   ```bash
   export RHCS_CLIENT_ID="YOUR_RHCS_CLIENT_ID"
   export RHCS_CLIENT_SECRET="YOUR_RHCS_CLIENT_SECRET"
   ```
   
   **方法2: 一時トークン（MachinePool作成時など、一部操作で必要）**
   ```bash
   # まず rosa login を実行
   rosa login --use-auth-code  # または --use-device-code
   
   # その後、トークンを取得
   export RHCS_TOKEN=$(rosa token)
   ```
   
   **重要: MachinePool作成時の認証について**
   
   - サービスアカウント（RHCS_CLIENT_ID / RHCS_CLIENT_SECRET）では、MachinePool作成時に
     403エラーが発生する場合があります。
   - その場合は、RHCS_TOKENを使用してください。
   - RHCS_TOKENは一時トークンで有効期限が短いため、長時間の `terraform apply` や
     自動化用途では注意が必要です。

3. **ROSA初期化**
   ```bash
   rosa verify permissions
   ```

## 使用方法

### 1. 自動デプロイスクリプトの使用（推奨）

最も簡単な方法は、提供されているデプロイスクリプトを使用することです：

```bash
# 環境変数を設定
source env.sh

# デプロイスクリプトを実行
./deploy.sh
```

このスクリプトは以下の2フェーズで環境を構築します：

#### フェーズ1: ネットワークリソースの構築
- VPC、サブネット、NAT Gateway、Internet Gatewayなどのネットワークリソースを作成
- `terraform/network/` ディレクトリで実行

#### フェーズ2: ROSAクラスターの構築
- フェーズ1で作成したネットワークリソースを使用してROSAクラスターを作成
- `terraform/cluster/` ディレクトリで実行
- クラスター構築には約30-40分かかります
- `rosa logs install --watch` で構築進行状況を監視

### 2. 手動デプロイ

手動でデプロイする場合：

#### ステップ 1: 設定ファイルの準備

```bash
# 環境変数を設定（推奨）
source env.sh
```

`env.sh` では以下の変数を設定します：
- `TF_VAR_aws_region` - AWSリージョン
- `TF_VAR_cluster_name` - クラスター名
- `TF_VAR_ocp_version` - OpenShiftバージョン
- `TF_VAR_billing_account` - AWS Billing Account（機密情報）
- その他の設定値

#### ステップ 2: フェーズ1 - ネットワークリソースの構築

```bash
cd terraform/network

# 初期化
terraform init

# 実行計画の確認
terraform plan

# デプロイ
terraform apply
```

#### ステップ 3: フェーズ2 - ROSAクラスターの構築

```bash
cd ../cluster

# ネットワーク情報を取得してterraform.tfvarsに設定
# （deploy.shスクリプトは自動的に行います）

# 初期化
terraform init

# 実行計画の確認
terraform plan

# デプロイ
terraform apply
```

⏱️ **注意**: ROSAクラスターの作成には約30-40分かかります。

#### ステップ 4: 出力情報の確認

```bash
# クラスター情報の表示
cd terraform/cluster
terraform output cluster_name
terraform output cluster_api_url
terraform output cluster_console_url

# 管理者パスワードの表示（機密情報）
terraform output cluster_admin_password

# Ansible用のJSON出力を保存
terraform output -json ansible_inventory_json > ../../ansible/cluster_info.json
```

### 2. クラスターへのログイン

```bash
# 管理者（cluster-admin）としてログイン
CLUSTER_API=$(terraform output -raw cluster_api_url)
ADMIN_USER=$(terraform output -raw cluster_admin_username)
ADMIN_PASS=$(terraform output -raw cluster_admin_password)

oc login "${CLUSTER_API}" -u "${ADMIN_USER}" -p "${ADMIN_PASS}"

# クラスター状態の確認
oc get nodes
oc get clusterversion
```

#### HTPasswd IDP ユーザー

Terraform で以下の HTPasswd ユーザーを事前作成できます：

- 管理者用 HTPasswd ユーザー:
  - ユーザー名: `admin`
  - パスワード: `TF_VAR_admin_password` で設定した値
- ワークショップユーザー:
  - ユーザー名: `user1` ～ `user50`
  - パスワード: すべて同一で、`TF_VAR_workshop_user_password` で設定した値

例: ワークショップユーザーでログインする場合

```bash
CLUSTER_API=$(terraform output -raw cluster_api_url)
oc login "${CLUSTER_API}" -u "user1" -p "${TF_VAR_workshop_user_password}"
```

### 3. Ansible による追加構成（次のステップ）

TerraformでROSAクラスターが構築された後、Ansibleを使用して以下の構成を行います：

- htpasswd Identity Provider の設定
- ワークショップユーザーの作成
- ArgoCD のインストールと設定
- その他のワークショップ環境の準備

```bash
cd ../ansible
# Ansible playbook の実行（準備中）
# ansible-playbook site.yml
```

## 環境の削除

環境を削除する場合は、削除スクリプトを使用することを推奨します：

```bash
./destroy.sh
```

このスクリプトは以下の2フェーズで環境を削除します：

#### フェーズ1: ROSAクラスターの削除
- `terraform/cluster/` で `terraform destroy` を実行
- `rosa logs uninstall --watch` でクラスター削除の進行状況を監視
- クラスター削除には約10-20分かかります
- トークン切れを考慮した自動再認証

#### フェーズ2: ネットワークリソースの削除
- フェーズ1でクラスターが完全に削除された後、`terraform/network/` で `terraform destroy` を実行
- VPC、サブネット、NAT Gatewayなどのネットワークリソースを削除

⚠️ **重要**: ネットワークリソースは、ROSAクラスターが完全に削除されるまで保持されます。これは、クラスターがネットワークリソースに依存しているためです。

### 手動削除

手動で削除する場合：

```bash
# フェーズ1: クラスターの削除
cd terraform/cluster
terraform destroy

# クラスター削除の完了を確認
rosa logs uninstall -c <cluster_name> --watch

# フェーズ2: ネットワークの削除（クラスター削除完了後）
cd ../network
terraform destroy
```

⚠️ **警告**: このコマンドは、作成されたすべてのリソース（クラスター、VPC、サブネットなど）を削除します。

**注意**: AnsibleやGitOpsで作成されたOpenShiftリソースは、クラスター削除とともに自動的に削除されます。

## 既知の問題

このセクションでは、現在把握している既知の問題と対処方法を記載しています。

### 1. RHCS_TOKEN の有効期限によるエラー

**問題**: クラスター構築時（特にMachinePool作成時）に `RHCS_TOKEN` が必要なケースがありますが、`RHCS_TOKEN` は一時トークンで有効期限が短いため、長時間の `terraform apply` 実行中にトークンが期限切れとなり、コマンドが失敗する場合があります。

**対処方法**:
- エラーが発生した場合は、`RHCS_TOKEN` を再取得してから `terraform apply` を再実行してください：
  ```bash
  # ROSAにログイン（必要に応じて）
  rosa login --use-auth-code  # または --use-device-code
  
  # トークンを再取得
  export RHCS_TOKEN=$(rosa token)
  
  # Terraformを再実行
  cd terraform/cluster
  terraform apply
  ```
- `deploy.sh` スクリプトを使用している場合、`additional_machine_pools` が定義されていると自動的に `RHCS_TOKEN` の取得を試みますが、長時間の操作ではトークンが期限切れになる可能性があります。

**回避策**:
- 可能な限り、サービスアカウント（`RHCS_CLIENT_ID` / `RHCS_CLIENT_SECRET`）を使用してください。ただし、MachinePool作成時など一部の操作では `RHCS_TOKEN` が必要な場合があります。

### 2. リソース削除時の依存関係エラー

**問題**: 環境削除時（`terraform destroy`）に、リソースの削除順序の関係からエラーが発生する可能性があります。特に、ネットワークリソース（VPC、サブネットなど）の削除時に、ROSAクラスターが作成したENI（Elastic Network Interface）などの依存リソースが完全に削除されていない場合に `DependencyViolation` エラーが発生することがあります。

**対処方法**:
- `destroy.sh` スクリプトを使用している場合、自動的にENIのクリーンアップを待機してから再試行します。
- 手動で削除する場合、エラーが発生したら数分待ってから再度 `terraform destroy` を実行してください：
  ```bash
  # エラーが発生した場合
  cd terraform/network
  # 数分待機（ENIのクリーンアップを待つ）
  sleep 300  # 5分待機
  
  # 再度実行
  terraform destroy
  ```
- クラスターが完全に削除されるまで待機してから、ネットワークリソースの削除を実行してください。

**回避策**:
- `destroy.sh` スクリプトを使用することで、自動的に適切な順序で削除が実行されます。

### 3. MachinePool作成時の権限エラー（403 Forbidden）

**問題**: TerraformでMachinePoolを作成する際、サービスアカウント（`RHCS_CLIENT_ID` / `RHCS_CLIENT_SECRET`）を使用している場合、403 Forbiddenエラーが発生することがあります。これは、サービスアカウントにMachinePool作成に必要な権限が不足している可能性があります。

**対処方法**:
- 一時的に `RHCS_TOKEN` を使用することで回避できます：
  ```bash
  # ROSAにログイン
  rosa login --use-auth-code  # または --use-device-code
  
  # トークンを取得
  export RHCS_TOKEN=$(rosa token)
  
  # Terraformを実行
  cd terraform/cluster
  terraform apply
  ```
- `deploy.sh` スクリプトを使用している場合、`additional_machine_pools` が定義されていると自動的に `RHCS_TOKEN` の取得を試みます。

**注意**:
- この問題は、サービスアカウントの権限設定に関する可能性があります。
- Red Hatサポートまたは社内のROSA担当者に確認して、サービスアカウントに適切な権限を付与する必要があるかもしれません。
- 現時点では、`RHCS_TOKEN` を使用することで回避できますが、長期的にはサービスアカウントの権限を適切に設定することが推奨されます。

## トラブルシューティング

### ROSA クォータエラー

```bash
rosa verify quota --region ap-northeast-1
```

クォータが不足している場合は、AWSサポートにクォータ引き上げをリクエストしてください。

### Terraform状態の確認

```bash
terraform state list
terraform state show <resource_name>
```

### ROSAクラスターの状態確認

```bash
rosa describe cluster -c mta-lightspeed
rosa logs install -c mta-lightspeed --watch
```

## プロジェクト構成

```
.
├── README.md                     # このファイル
├── deploy.sh                     # 環境構築スクリプト（2フェーズ）
├── destroy.sh                    # 環境削除スクリプト（2フェーズ）
├── env.sh                        # 環境変数設定ファイル
├── terraform/                    # Terraform設定
│   ├── network/                 # ネットワークリソース（フェーズ1）
│   │   ├── versions.tf          # AWSプロバイダー設定
│   │   ├── variables.tf         # 変数定義
│   │   ├── main.tf             # VPC/ネットワーク設定
│   │   ├── outputs.tf          # 出力定義
│   │   └── terraform.tfvars.example
│   └── cluster/                 # ROSAクラスター（フェーズ2）
│       ├── versions.tf          # AWS/RHCSプロバイダー設定
│       ├── variables.tf         # 変数定義
│       ├── main.tf              # ROSAクラスター設定
│       ├── locals.tf            # ローカル変数
│       ├── outputs.tf           # 出力定義
│       └── terraform.tfvars.example
├── ansible/                      # Ansible設定（準備中）
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
└── gitops/                       # GitOps設定（準備中）
    └── argocd/
```

### 2フェーズ構成の理由

ROSAクラスターとネットワークリソースを2つのTerraformに分離している理由：

1. **削除順序の制御**: ROSAクラスターは削除に時間がかかるため（約10-20分）、クラスターが完全に削除されるまでネットワークリソースを保持する必要があります。
2. **依存関係の明確化**: クラスターはネットワークリソースに依存していますが、削除時は逆の順序で実行する必要があります。
3. **柔軟性**: ネットワークリソースを再利用したり、別のクラスターで使用したりする可能性があります。

## 参考リンク

- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)
- [Red Hat OpenShift Documentation](https://docs.openshift.com/)
- [Konveyor AI](https://www.konveyor.io/)

## ライセンス

MIT License

## サポート

問題が発生した場合は、Issueを作成してください。

