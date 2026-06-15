# 環境プロファイルガイド

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────────┐
│                     Configuration Layer                          │
│  profiles/{name}.env  ─→  env.sh  ─→  環境変数                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     Infrastructure Layer                         │
│  deploy.sh  ─→  terraform/network  ─→  terraform/cluster        │
│                                         └─ GPU pool (auto)      │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      Bootstrap Layer                             │
│  ansible/playbooks/site.yml (条件実行)                           │
│    ├─ install_gitops.yml          (gitops)                      │
│    ├─ setup_operator_configmaps.yml (configmaps)                │
│    ├─ setup_tackle_secret.yml     (tackle_secret)               │
│    ├─ setup_odh_storage.yml       (odh_storage)                 │
│    └─ setup_loki_storage.yml      (loki_storage)                │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                       GitOps Layer                               │
│  App-of-Apps ─→ gitops/environments/{env}/apps/*.yml            │
│                  └─ gitops/operators/{operator}/                 │
│                  └─ gitops/environments/{env}/resources/         │
└─────────────────────────────────────────────────────────────────┘
```

## 環境比較マトリクス

| オペレーター | mta-full | mta-light | observability | ai-serving |
|------------|:--------:|:---------:|:-------------:|:----------:|
| Node Feature Discovery | x | | | x |
| NVIDIA GPU Operator | x | | | x |
| OpenShift AI (RHOAI) | x | | | x |
| Authorino | x | | | |
| Dev Spaces | x | x | | |
| CloudNativePG | x | x | | |
| Keycloak | x | x | | |
| MTA | x | x | | |
| Loki | | | x | |
| Network Observability | | | x | |

## プロファイル設定比較

| 設定項目 | mta-full | mta-light | observability | ai-serving |
|---------|----------|-----------|---------------|------------|
| マシンタイプ | m6a.2xlarge | m6a.2xlarge | m6a.xlarge | m6a.2xlarge |
| ワーカー数 | 3 | 2 | 2 | 2 |
| GPU | g5.xlarge x1 | なし | なし | g5.2xlarge x1 |
| Ansible playbooks | gitops,configmaps,tackle_secret,odh_storage | gitops,configmaps,tackle_secret | gitops,loki_storage | gitops,configmaps,odh_storage |
| ユーザー数 | 30 | 20 | 10 | 5 |

## 使い方

### 既存プロファイルでデプロイ

```bash
export PROFILE="mta-full"
source env.sh
./deploy.sh
```

### 新しい環境を作成

```bash
# 1. スキャフォールド生成
./scripts/create-env.sh my-workshop

# 2. プロファイル編集
vim profiles/my-workshop.env

# 3. オペレーター Application を配置
cp gitops/environments/mta/apps/devspaces-operator.yml \
   gitops/environments/my-workshop/apps/

# 4. デプロイ
export PROFILE="my-workshop"
source env.sh
./deploy.sh
```

### Cursor AI に依頼する場合

```
「quarkus ワークショップ環境を作成して。DevSpaces と Keycloak が必要。
 ユーザー15人、GPU は不要。」
```

AI が自動的に:
1. `scripts/create-env.sh` を実行
2. プロファイルの変数を埋める
3. 必要な Application YAML を配置

## ROSA の制約事項

| 制約 | 内容 | 対処法 |
|------|------|--------|
| 最小ノード数 | 初期プール 2ノード、削除不可 | 受け入れる |
| インスタンスタイプ変更 | 作成後は変更不可 | 新しい MachinePool を追加 |
| STS (IAM Role) | 常に作成される | 受け入れる |
| HTPasswd IDP | ユーザー動的追加に制限あり | Terraform で事前定義 |
| OCP バージョン | 作成時に決定 | アップグレードは別操作 |

## ディレクトリ構造

```
mta-demo-env/
├── profiles/                           # 環境プロファイル定義
│   ├── mta-full.env
│   ├── mta-light.env
│   ├── observability.env
│   ├── ai-serving.env
│   └── custom-example.env
├── deploy.sh                           # デプロイオーケストレーター
├── destroy.sh                          # 削除オーケストレーター
├── env.sh                              # 環境変数 (プロファイル読み込み付き)
├── terraform/
│   ├── network/                        # VPC, サブネット, NAT
│   └── cluster/                        # ROSA HCP, IDP, MachinePool
├── ansible/
│   └── playbooks/site.yml             # 条件実行対応
├── gitops/
│   ├── operators/                      # 共有オペレーター定義
│   └── environments/                   # 環境ごとの構成
│       ├── mta/apps/
│       ├── mta_light/apps/
│       ├── observ/apps/
│       └── {custom}/apps/
├── scripts/
│   └── create-env.sh                   # 環境スキャフォールド
└── .cursor/rules/
    └── environment-management.md       # AI 向けルール
```
