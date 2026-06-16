# ROSA HCP ワークショップ環境構築

ROSA HCP (Red Hat OpenShift on AWS) 上にワークショップ/デモ環境を自動構築するための Terraform、Ansible、GitOps 設定です。

プロファイルシステムにより、MTA、OpenShift AI、Observability 等の異なる構成を同じスクリプトで管理できます。

## クイックスタート

```bash
# 1. プロファイルを選択してデプロイ
export PROFILE="openshift-ai"
./deploy.sh

# 2. 削除
export PROFILE="openshift-ai"
./destroy.sh
```

## 利用可能なプロファイル

| プロファイル | 用途 | GPU | 主なオペレーター |
|------------|------|:---:|----------------|
| `mta-full` | MTA + AI フルワークショップ | g5.xlarge x1 | MTA, RHOAI, DevSpaces, Keycloak, CNPG |
| `mta-light` | MTA 最小構成 | なし | MTA, DevSpaces, Keycloak, CNPG |
| `openshift-ai` | OpenShift AI 3.x 検証 | g5.xlarge x1 | RHOAI, NVIDIA GPU, NFD |
| `observability` | Network Observability | なし | Loki, Network Observability |
| `ai-serving` | AI モデルサービング | g5.2xlarge x1 | RHOAI, NVIDIA GPU, NFD |

## 前提条件

### 必要なツール

- **Terraform** (>= 1.5.0) — `brew install terraform`
- **AWS CLI** (>= 2.0) — `brew install awscli`
- **ROSA CLI** — `brew install rosa-cli`
- **Ansible** (>= 2.14) — `brew install ansible`
- **OpenShift CLI (oc)** — `brew install openshift-cli`
- **jq** — `brew install jq`

Linux の場合は各ツールの公式ドキュメントを参照してください。

### 必要な認証情報

1. **AWS 認証情報** — Access Key ID / Secret Access Key（EC2, VPC, IAM 権限）
2. **RHCS サービスアカウント** — Terraform RHCS プロバイダー用（`RHCS_CLIENT_ID` / `RHCS_CLIENT_SECRET`）
3. **ROSA CLI ログイン** — `rosa login --use-auth-code` または `--use-device-code`

## 使用方法

### 1. 認証情報の設定

```bash
cp env.sh.example env.sh
# env.sh を編集して AWS キー、RHCS トークン等を記入
```

`env.sh` には認証情報のみを記載します（環境構成はプロファイルで管理）。

### 2. デプロイ

```bash
export PROFILE="openshift-ai"   # 使いたい環境を指定
./deploy.sh
```

`deploy.sh` は以下を順番に実行します：

1. プロファイル読み込み（`profiles/{PROFILE}.env`）
2. `env.sh` から認証情報を読み込み
3. **Network** — VPC, Subnet, NAT Gateway を Terraform で構築
4. **Cluster** — ROSA HCP クラスター + GPU ノードプール（該当する場合）を構築
5. **Ansible** — GitOps Operator インストール + Console Plugin 有効化 + App-of-Apps 設定
6. **ArgoCD Sync** — プロファイルに応じたオペレーターが自動デプロイ

クラスター構築には約30-40分かかります。

### 3. 削除

```bash
export PROFILE="openshift-ai"
./destroy.sh
```

`destroy.sh` は以下を実行します：

1. ROSA クラスター削除（Terraform or ROSA CLI）
2. IAM ロール / OIDC プロバイダーのクリーンアップ
3. VPC 内の孤立リソース（ENI, Security Group 等）のクリーンアップ
4. ネットワークリソース削除

### 4. GITOPS_ENV の変更（環境切り替え）

既にクラスターがある状態で GitOps 環境だけ切り替える場合：

```bash
export PROFILE="mta-light"    # 新しいプロファイルに変更
./deploy.sh                    # 再実行（クラスターは変更なし、ArgoCD の設定だけ更新）
```

ArgoCD の App-of-Apps パスが更新され、新しい環境のオペレーターが Sync されます。

## 新しい環境の追加

### スキャフォールド生成

```bash
./scripts/create-env.sh quarkus-workshop
```

以下が生成されます：
- `profiles/quarkus-workshop.env` — プロファイル設定（雛形）
- `gitops/environments/quarkus-workshop/apps/` — ArgoCD Application 配置先
- `gitops/environments/quarkus-workshop/resources/` — カスタムリソース配置先

### プロファイルのカスタマイズ

```bash
vim profiles/quarkus-workshop.env
```

### オペレーターの追加

既存環境からコピー：

```bash
cp gitops/environments/mta/apps/devspaces-operator.yml \
   gitops/environments/quarkus-workshop/apps/
```

### Cursor AI に依頼する場合

```
「quarkus-workshop 環境に DevSpaces と Keycloak を追加して。ユーザー15人、GPU 不要。」
```

## プロファイルの変数

| 変数 | 説明 | 例 |
|------|------|-----|
| `PROFILE_NAME` | プロファイル識別名 | `openshift-ai` |
| `GITOPS_ENV` | GitOps 環境ディレクトリ名 | `openshift-ai` |
| `CLUSTER_VIA` | クラスター構築方式 | `terraform`, `rosa-cli` |
| `TF_VAR_rosa_machine_type` | ワーカーインスタンスタイプ | `m6a.2xlarge` |
| `TF_VAR_worker_pool_replicas` | ワーカーノード数 | `2` |
| `TF_VAR_availability_zone_count` | AZ 数 | `1` |
| `GPU_MACHINE_TYPE` | GPU インスタンスタイプ（空=なし） | `g5.xlarge` |
| `GPU_REPLICAS` | GPU ノード数 | `1` |
| `RUN_ANSIBLE` | Ansible 実行有無 | `true` |
| `ANSIBLE_PLAYBOOKS` | 実行する playbook | `gitops,configmaps,odh_storage` |
| `TF_VAR_admin_count` | 管理者ユーザー数 | `1` |
| `TF_VAR_workshop_user_count` | ワークショップユーザー数 | `10` |

## プロジェクト構成

```
.
├── deploy.sh                    # デプロイオーケストレーター
├── destroy.sh                   # 削除オーケストレーター
├── env.sh                       # 認証情報（git 管理外）
├── profiles/                    # 環境プロファイル
│   ├── mta-full.env
│   ├── mta-light.env
│   ├── openshift-ai.env
│   ├── observability.env
│   └── ai-serving.env
├── terraform/
│   ├── network/                 # VPC, Subnet, NAT（フェーズ1）
│   └── cluster/                 # ROSA HCP, IDP, MachinePool（フェーズ2）
├── ansible/
│   ├── playbooks/site.yml       # 条件実行対応
│   └── roles/openshift_gitops/  # GitOps + Console Plugin
├── gitops/
│   ├── operators/               # 共有オペレーター定義
│   └── environments/            # 環境ごとの構成
│       ├── mta/apps/
│       ├── mta-light/apps/
│       ├── openshift-ai/apps/
│       └── observ/apps/
├── scripts/
│   └── create-env.sh            # 環境スキャフォールド
├── docs/
│   └── environments.md          # 環境比較マトリクス
└── .cursor/rules/
    └── environment-management.md  # AI 向けルール
```

## トラブルシューティング

### IAM Role が既に存在するエラー

```
EntityAlreadyExists: Role with name xxx-account-HCP-ROSA-Worker-Role already exists
```

前回の `destroy.sh` で IAM Role が削除されなかった場合に発生します。
`destroy.sh` は現在すべてのモードで IAM クリーンアップを実行するよう修正済みです。

手動で削除する場合：
```bash
rosa delete account-roles --prefix "<cluster-name>-account" --mode auto --yes
rosa delete operator-roles --prefix "<cluster-name>-operator-roles" --mode auto --yes
```

### VPC 削除が DependencyViolation で失敗

`destroy.sh` が自動的に VPC 内の孤立リソース（Security Group, ENI, VPC Endpoint）を削除します。
手動の場合は AWS Console から該当リソースを削除してください。

### ArgoCD の app path does not exist エラー

`GITOPS_ENV` とディレクトリ名が一致しているか確認してください：
```bash
ls gitops/environments/
# プロファイルの GITOPS_ENV と同じ名前のディレクトリがあるか確認
```

### ROSA クォータエラー

```bash
rosa verify quota --region ap-northeast-1
```

## 参考リンク

- [ROSA Documentation](https://docs.openshift.com/rosa/welcome/index.html)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs)
- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
