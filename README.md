# MTA for Developer Lightspeed ワークショップ環境構築

このリポジトリは、MTA for Developer Lightspeedワークショップのための環境を自動構築するためのTerraform、Ansible、GitOps設定を含んでいます。

## 概要

- **Terraform**: Red Hat OpenShift for AWS (ROSA) HCP クラスターの構築
- **Ansible**: OpenShift IDP設定、ArgoCD構築などの構成管理
- **GitOps (ArgoCD)**: Operatorとアプリケーションの継続的デリバリー（ApplicationSetを使用）

## 前提条件

### 対応OS

- **macOS**: 完全対応
- **Linux**: 完全対応（Ubuntu、RHEL、CentOS、Fedoraなど）
- **Windows**: ネイティブWindowsでは動作しません。WSL2（Windows Subsystem for Linux 2）での使用を推奨します *未検証

### 必要なツール

1. **Terraform** (>= 1.5.0)
   
   **macOS:**
   ```bash
   brew install terraform
   ```
   
   **Linux (Ubuntu/Debian):**
   ```bash
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```
   
   **Linux (RHEL/CentOS/Fedora):**
   ```bash
   sudo dnf install -y dnf-plugins-core
   sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
   sudo dnf install -y terraform
   ```

2. **AWS CLI** (>= 2.0)
   
   **macOS:**
   ```bash
   brew install awscli
   ```
   
   **Linux:**
   ```bash
   # インストーラーを使用（推奨）
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # または、パッケージマネージャーを使用
   # Ubuntu/Debian:
   sudo apt install awscli
   # RHEL/CentOS/Fedora:
   sudo dnf install awscli
   ```

3. **ROSA CLI**
   
   **macOS:**
   ```bash
   brew install rosa-cli
   ```
   
   **Linux:**
   ```bash
   wget https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz
   tar xzf rosa-linux.tar.gz
   sudo mv rosa /usr/local/bin/
   ```

4. **Ansible** (>= 2.14) - 後続のステップで使用
   
   **macOS:**
   ```bash
   brew install ansible
   ```
   
   **Linux (Ubuntu/Debian):**
   ```bash
   sudo apt update
   sudo apt install ansible
   ```
   
   **Linux (RHEL/CentOS/Fedora):**
   ```bash
   sudo dnf install ansible
   ```
   
   **pipを使用する場合（全OS共通）:**
   ```bash
   pip3 install ansible
   ```

5. **OpenShift CLI (oc)**
   
   **macOS:**
   ```bash
   brew install openshift-cli
   ```
   
   **Linux:**
   ```bash
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
   tar xzf openshift-client-linux.tar.gz
   sudo mv oc /usr/local/bin/
   ```

6. **jq** (JSONパーサー、推奨)
   
   **macOS:**
   ```bash
   brew install jq
   ```
   
   **Linux (Ubuntu/Debian):**
   ```bash
   sudo apt install jq
   ```
   
   **Linux (RHEL/CentOS/Fedora):**
   ```bash
   sudo dnf install jq
   ```

### Windowsでの使用について

このスクリプトはbashスクリプトのため、**ネイティブWindowsでは動作しません**。

Windowsで使用する場合は、**WSL2 (Windows Subsystem for Linux 2)** を使用してください：

1. **WSL2のインストール**
   ```powershell
   # PowerShell (管理者権限)で実行
   wsl --install
   ```

2. **Linuxディストリビューションのインストール**
   - UbuntuなどのLinuxディストリビューションをインストール
   - 上記のLinux手順に従ってツールをインストール

3. **WSL2での実行**
   - WSL2のターミナルでこのリポジトリをクローン
   - 上記のLinux手順に従ってセットアップ

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
   
   TerraformのRHCSプロバイダーは、サービスアカウントを使用します：
   
   ```bash
   export RHCS_CLIENT_ID="YOUR_RHCS_CLIENT_ID"
   export RHCS_CLIENT_SECRET="YOUR_RHCS_CLIENT_SECRET"
   ```

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
- OpenShift GitOps (ArgoCD) のインストールと設定
- Operator RoleARN ConfigMapの作成
- その他のワークショップ環境の準備

```bash
cd ../ansible
ansible-playbook site.yml
```

### 4. ArgoCD ApplicationSetによるOperator管理

このプロジェクトでは、ArgoCDのApplicationSetを使用して、すべてのOperatorを管理します。

#### Operator管理の仕組み

- **ArgoCD ApplicationSet**: OperatorのSubscriptionリソースを管理
  - NFD Operator
  - NVIDIA GPU Operator
  - OpenShift AI Operator
  - Authorino Operator
  - DevSpaces Operator
  - Cloud Native PostgreSQL Operator
  - Red Hat build of Keycloak Operator

- **ArgoCD**: アプリケーションと環境固有リソースの管理
  - `gitops/environments/{env-name}/resources/` 配下のリソース
  - 環境ごとに異なる設定やカスタムリソース

#### ApplicationSetの設定

ApplicationSetはAnsible playbook実行時に自動的に適用され、各Operator用のApplicationを動的に生成します。

ApplicationSet定義は `gitops/applicationsets/operators/operators-applicationset.yaml` に配置され、Operatorマニフェストは `gitops/operators/` ディレクトリに配置されます。

詳細は `gitops/applicationsets/operators/README.md` を参照してください。

#### DevSpaces用AWS Role ARNの設定

DevSpaces OperatorのインストールにはAWS IAM Role ARNが必要です。Ansible playbookが自動的にTerraform outputからRole ARNを取得し、`operator-rolearns` ConfigMapに保存します。ApplicationSetがこのConfigMapからRoleARNを読み取り、Helm Chartを通じてSubscriptionに注入します。

Role ARNの形式: `arn:aws:iam::{account_id}:user/{iam_user_name}`

### 5. GitOps環境の切り替え

このスクリプトは、1つのスクリプトで複数のGitOps環境に対応できます。環境を切り替えるには、`env.sh`で`GITOPS_ENV`環境変数を設定します。

#### 環境の種類

- **mta** (デフォルト): MTA for Developer Lightspeedワークショップ用の環境
- **other**: その他のカスタム環境

#### 使用方法

1. **環境変数の設定** (`env.sh`):

```bash
# MTA環境を使用（デフォルト）
export GITOPS_ENV="mta"

# または、その他の環境を使用
export GITOPS_ENV="other"
```

2. **デプロイスクリプトの実行**:

```bash
source env.sh
./deploy.sh
```

`deploy.sh`は自動的に`GITOPS_ENV`を読み込み、Ansibleに渡します。Ansibleは`gitops/environments/{GITOPS_ENV}/apps/`ディレクトリを監視するようにArgoCDのapp-of-appsを設定します。

#### ディレクトリ構造

```
gitops/
├── applicationsets/
│   └── operators/
│       └── operators-applicationset.yaml  # ApplicationSet定義
├── operators/
│   ├── nfd-operator/              # Operatorマニフェスト
│   ├── nvidia-operator/
│   ├── devspaces/                 # Helm Chart（RoleARN注入用）
│   └── ...
└── environments/
    ├── mta/
    │   ├── apps/                # Application定義
    │   ├── operators/           # 環境専用Operator（オプション）
    │   └── resources/           # 環境専用リソース
    │       ├── configmaps/      # ConfigMap
    │       ├── secrets/         # Secret（機密情報）
    │       └── custom-resources/ # カスタムリソース
    └── other/
        ├── apps/
        ├── operators/           # オプション
        └── resources/           # 環境専用リソース
```

#### 環境専用リソースの使用

環境ごとに異なるリソース（ConfigMap、Secret、カスタムリソースなど）が必要な場合は、`gitops/environments/{env-name}/resources/` ディレクトリに配置します。

**例: 環境専用リソースをデプロイするApplication定義**

`gitops/environments/mta/apps/custom-resources.yml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mta-custom-resources
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/kanekoh/mta-workshop-env.git
    targetRevision: main
    path: gitops/environments/mta/resources/custom-resources
  destination:
    server: https://kubernetes.default.svc
    namespace: your-namespace
```

詳細は `gitops/environments/{env-name}/resources/README.md` を参照してください。

#### 新しい環境の追加

新しい環境を追加する場合：

1. `gitops/environments/{env-name}/apps/` ディレクトリを作成
2. `gitops/environments/{env-name}/resources/` ディレクトリを作成（環境専用リソース用）
3. そのディレクトリにApplication定義ファイル（`*.yml`）を配置
4. `env.sh`で`GITOPS_ENV="{env-name}"`を設定
5. `./deploy.sh`を実行

**注意**: 環境名に対応するディレクトリが`gitops/environments/{GITOPS_ENV}/apps/`に存在する必要があります。

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

### Terraformインポート時のNull conditionエラー

既存のROSAクラスターをTerraform Stateにインポートする際、以下のエラーが発生する場合があります：

```
Error: Null condition

  on .terraform/modules/rosa_hcp/modules/rosa-cluster-hcp/main.tf line 142, in resource "rhcs_hcp_default_ingress" "default_ingress":
 142:   count   = rhcs_cluster_rosa_hcp.rosa_hcp_cluster.wait_for_create_complete ? 1 : 0
    │
    │ rhcs_cluster_rosa_hcp.rosa_hcp_cluster.wait_for_create_complete is null

The condition value is null. Conditions must either be true or false.
```

#### 原因

`terraform import`で既存クラスターをインポートすると、Stateには実際のリソース属性のみが記録されます。`wait_for_create_complete`は設定パラメータであり、既存リソースには存在しないため、Stateでは`null`になります。しかし、`rosa-hcp`モジュール内の条件式は`null`を許可しないため、エラーが発生します。

#### 対処方法

Terraform Stateファイルを直接編集して、`wait_for_create_complete`属性を`true`に設定します。

1. **クラスターIDを取得**

   HybridCloudConsole（Red Hat OpenShift Cluster Manager）からクラスターIDを取得します。
   または、`rosa describe cluster -c <cluster_name>`コマンドでIDを確認できます。

2. **Stateファイルのバックアップ**

   ```bash
   cd terraform/cluster
   cp terraform.tfstate terraform.tfstate.backup
   ```

3. **Stateファイルを編集**

   `terraform.tfstate`の`resources`配列に、以下のリソース定義を追加します：

   ```json
   {
     "module": "module.rosa_hcp.module.rosa_cluster_hcp",
     "mode": "managed",
     "type": "rhcs_cluster_rosa_hcp",
     "name": "rosa_hcp_cluster",
     "provider": "provider[\"registry.terraform.io/terraform-redhat/rhcs\"]",
     "instances": [
       {
         "schema_version": 0,
         "attributes": {
           "id": "<cluster_id>",
           "wait_for_create_complete": true
         },
         "sensitive_attributes": [],
         "private": "eyJzY2hlbWFfdmVyc2lvbiI6IjAifQ==",
         "dependencies": []
       }
     ]
   }
   ```

   `<cluster_id>`は、HybridCloudConsoleから取得したクラスターIDに置き換えてください。

4. **検証**

   ```bash
   terraform state list | grep rosa_hcp_cluster
   terraform plan
   ```

   エラーが解消され、`terraform plan`が正常に実行できることを確認してください。

5. **削除の確認**

   Stateに正しく追加されていれば、`terraform destroy`でクラスターを削除できるようになります。

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
├── ansible/                      # Ansible設定
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
│       └── openshift_gitops/     # OpenShift GitOps (ArgoCD) ロール
└── gitops/                       # GitOps設定（ArgoCD用）
    ├── applicationsets/          # ApplicationSet定義
    │   └── operators/           # Operator用ApplicationSet
    ├── operators/                # Operatorマニフェスト
    │   ├── nfd-operator/
    │   ├── nvidia-operator/
    │   ├── devspaces/           # Helm Chart（RoleARN注入用）
    │   └── ...
    └── environments/             # 環境別設定
        ├── mta/                 # MTA環境
        │   ├── apps/            # Application定義ファイル
        │   ├── operators/       # 環境専用Operator（オプション）
        │   └── resources/       # 環境専用リソース
        │       ├── configmaps/
        │       ├── secrets/
        │       └── custom-resources/
        └── other/                # その他の環境（例）
            ├── apps/             # Application定義ファイル
            ├── operators/        # オプション
            └── resources/        # 環境専用リソース
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

