# クイックスタートガイド

このガイドでは、最小限のステップでROSA環境を構築する方法を説明します。

## 🚀 5分でスタート

### ステップ 1: 必要なツールのインストール

```bash
# macOS の場合
brew install terraform awscli rosa-cli openshift-cli ansible
```

### ステップ 2: 認証情報の準備

1. **AWS認証情報**
   - AWS Management Consoleから取得
   - IAMユーザーに適切な権限を付与

2. **Red Hat アカウント / RHCS サービスアカウント**
   - Red Hat のアカウント（SSO認証用）
   - 有効なROSAサブスクリプション
   - Terraform 用には RHCS サービスアカウントのクライアントID/シークレットを用意すると便利です

### ステップ 3: 環境変数の設定

```bash
# 環境変数ファイルをコピー
cp env.sh.example env.sh

# env.sh を編集して実際の値を設定
vim env.sh

# 環境変数を読み込む
source env.sh
```

`env.sh` の設定例：
```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

ROSAにログイン：
```bash
# ブラウザ環境の場合
rosa login --use-auth-code

# ブラウザレス環境の場合
rosa login --use-device-code
```

Terraform (RHCS provider) 向けの認証方法:

以下のサイトで登録したサービスアカウントを利用してください。登録時にクライアントIDとシークレットが表示されます。
https://console.redhat.com/iam/service-accounts/

```bash
export RHCS_CLIENT_ID="YOUR_RHCS_CLIENT_ID"
export RHCS_CLIENT_SECRET="YOUR_RHCS_CLIENT_SECRET"
```

### ステップ 4: Terraform設定

主要な設定は `env.sh` で環境変数として管理されているため、通常は追加の設定は不要です。

```bash
cd terraform

# 必要に応じて terraform.tfvars をカスタマイズ
# （通常は env.sh の設定で十分です）
cp terraform.tfvars.example terraform.tfvars
```

**注意**: `env.sh` で `TF_VAR_*` 環境変数を設定しているため、以下の値は自動的に認識されます：
- リージョン (TF_VAR_aws_region)
- クラスター名 (TF_VAR_cluster_name)
- OCPバージョン (TF_VAR_ocp_version)
- Billing Account (TF_VAR_billing_account)
- その他すべての設定

### ステップ 5: デプロイ実行

#### 方法A: ワンコマンドデプロイ（推奨）

```bash
# プロジェクトルートで実行
./deploy.sh
```

このスクリプトは自動的に：
- 必要なツールの確認
- ROSAへのログイン
- Terraformによるクラスター作成
- クラスターへのアクセス確認

を実行します。

#### 方法B: 手動デプロイ

```bash
# ROSA にログイン
# ブラウザ環境の場合
rosa login --use-auth-code
# または、ブラウザレス環境の場合
rosa login --use-device-code

# AWS権限の確認
rosa verify permissions --region ap-northeast-1
rosa verify quota --region ap-northeast-1

# Terraform でデプロイ
cd terraform
terraform init
terraform plan
terraform apply

# クラスター情報の確認
terraform output cluster_console_url
terraform output cluster_admin_password
```

### ステップ 6: クラスターにログイン

```bash
# 出力された情報を使用
oc login <API_URL> -u cluster-admin -p <PASSWORD>

# クラスター状態の確認
oc get nodes
oc get clusterversion
```

### ステップ 7: OpenShift Console にアクセス

ブラウザで Console URL を開き、cluster-admin でログインします。

## ⏱️ 所要時間

- 準備: 5-10分
- クラスター作成: 30-40分
- 合計: 約45-50分

## 🔧 トラブルシューティング

### エラー: "Insufficient quota"

```bash
# クォータを確認
rosa verify quota --region ap-northeast-1

# AWSサポートにクォータ引き上げをリクエスト
```

### エラー: "Authentication failed" または "Not logged in"

```bash
# ROSAに再ログイン
# ブラウザ環境の場合
rosa login --use-auth-code

# ブラウザレス環境の場合
rosa login --use-device-code

# ログイン状態の確認
rosa whoami
```

### エラー: Terraform実行時のエラー

```bash
# Terraformの状態を確認
terraform state list

# 特定のリソースを確認
terraform state show <resource_name>

# 必要に応じてリソースを削除
terraform destroy
```

## 🗑️ 環境の削除

```bash
cd terraform
terraform destroy
```

⚠️ これにより、クラスター含めすべてのリソースが削除されます。

## 📚 次のステップ

1. [README.md](README.md) - 詳細なドキュメント
2. [ansible/README.md](ansible/README.md) - Ansible設定
3. ROSA公式ドキュメント - https://docs.openshift.com/rosa/

## 💡 ヒント

### コスト削減

```bash
# env.sh でノード数を最小化
export TF_VAR_rosa_replicas="2"
export TF_VAR_rosa_machine_type="m6a.xlarge"  # より小さいインスタンス
```

### デバッグモード

```bash
# Terraform詳細ログ
export TF_LOG=DEBUG
terraform apply

# ROSA CLI詳細ログ
rosa create cluster --debug
```

### クラスターの状態確認

```bash
# ROSA CLIで確認
rosa describe cluster -c mta-lightspeed
rosa logs install -c mta-lightspeed --watch

# OpenShift CLIで確認
oc get co  # Cluster Operators
oc get nodes
oc get pods -A  # すべてのPod
```

## 🤝 サポート

問題が発生した場合：
1. [README.md](README.md)のトラブルシューティングセクションを確認
2. GitHubでIssueを作成
3. Red Hatサポートに連絡（有効なサブスクリプションが必要）

