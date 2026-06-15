---
description: ROSA ワークショップ環境の作成・カスタマイズ・管理を行うときのルール
globs:
  - profiles/*.env
  - gitops/environments/**
  - deploy.sh
  - destroy.sh
  - scripts/create-env.sh
---

# 環境管理ルール

このプロジェクトは ROSA HCP (Red Hat OpenShift on AWS) 上にワークショップ/デモ環境を構築するためのものです。

## アーキテクチャ（3レイヤー）

1. **Infrastructure (Terraform)** — VPC + ROSA クラスター + MachinePool
2. **Bootstrap (Ansible)** — OpenShift GitOps インストール + シークレット設定
3. **GitOps (ArgoCD)** — オペレーター + 環境固有リソースのデプロイ

## プロファイルシステム

環境切り替えは `profiles/*.env` で管理されます。

```bash
export PROFILE="mta-full"   # プロファイル選択
source env.sh               # 読み込み（プロファイル + 認証情報）
./deploy.sh                 # デプロイ
```

### プロファイルの変数

| 変数 | 説明 | 選択肢 |
|------|------|--------|
| `PROFILE_NAME` | プロファイル識別名 | 任意の文字列 |
| `GITOPS_ENV` | GitOps 環境名 | `gitops/environments/` 内のディレクトリ名 |
| `CLUSTER_VIA` | クラスター構築方式 | `terraform`, `rosa-cli` |
| `TF_VAR_rosa_machine_type` | ワーカーインスタンスタイプ | `m6a.xlarge`, `m6a.2xlarge`, `m6a.4xlarge` |
| `TF_VAR_worker_pool_replicas` | ワーカーノード数 | 2以上の整数 |
| `TF_VAR_availability_zone_count` | AZ 数 | `1` or `3` |
| `GPU_MACHINE_TYPE` | GPU ノードタイプ（空=なし） | `g4dn.xlarge`, `g5.xlarge`, `g5.2xlarge`, `g6.xlarge` |
| `GPU_REPLICAS` | GPU ノード数 | 0以上の整数 |
| `RUN_ANSIBLE` | Ansible 実行有無 | `true`, `false` |
| `ANSIBLE_PLAYBOOKS` | 実行する playbook | カンマ区切り: `gitops,configmaps,tackle_secret,odh_storage,loki_storage` |
| `TF_VAR_admin_count` | 管理者ユーザー数 | 1以上 |
| `TF_VAR_workshop_user_count` | ワークショップユーザー数 | 1以上 |

## 新しい環境を作成する手順

1. スキャフォールドを実行:
   ```bash
   ./scripts/create-env.sh <env-name>
   ```

2. プロファイルを編集:
   - `profiles/<env-name>.env` の変数を埋める

3. 必要なオペレーターの Application YAML を配置:
   - `gitops/environments/<env-name>/apps/` に配置

4. 必要に応じてカスタムリソースを追加:
   - `gitops/environments/<env-name>/resources/` に配置

## 利用可能なオペレーター

以下のオペレーターが `gitops/operators/` に定義済みです:

| オペレーター | パス | 前提条件 | ANSIBLE_PLAYBOOKS |
|------------|------|----------|-------------------|
| Node Feature Discovery | `gitops/operators/nfd-operator` | GPU 使用時に必須 | gitops |
| NVIDIA GPU Operator | `gitops/operators/nvidia-operator` | NFD 必須、GPU ノード必須 | gitops |
| OpenShift AI (RHOAI) | `gitops/operators/openshift-ai` | GPU 推奨 | gitops,odh_storage |
| Authorino | `gitops/operators/authorino` | — | gitops |
| Dev Spaces | `gitops/operators/devspaces` | RoleARN 必要 | gitops,configmaps |
| CloudNativePG | `gitops/operators/cnpg-operator` | RoleARN 必要 | gitops,configmaps |
| Keycloak | `gitops/operators/keycloak-operator` | CNPG 推奨 | gitops |
| MTA | `gitops/operators/mta-operator` | RoleARN 必要 | gitops,configmaps,tackle_secret |
| Loki | `gitops/operators/loki` | — | gitops,loki_storage |
| Network Observability | `gitops/operators/network-observability` | Loki 必須 | gitops,loki_storage |

## Application YAML のフォーマット

`gitops/environments/{env}/apps/` に置く Application YAML:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <operator-name>
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kanekoh/mta-workshop-env.git
    targetRevision: main
    path: gitops/operators/<operator-dir>
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
```

## ROSA の制約（変更不可）

- 初期ワーカープール: 最低2ノード、削除不可
- クラスター作成後にインスタンスタイプ変更不可（新 MachinePool で対応）
- STS IAM Role は常に作成される
- OpenShift バージョンは作成時に決定

## 依存関係ルール

オペレーターを追加する際は以下の依存関係に注意:

- **GPU 系**: `nfd-operator` → `nvidia-operator` → `openshift-ai-operator` の順序
- **MTA**: `cnpg-operator` + `keycloak-operator` が推奨（Tackle の DB/認証）
- **Network Observability**: `loki-operator` が必須
- **DevSpaces**: 単独で動作可能

## ユーザーから環境作成を依頼されたとき

1. まず `./scripts/create-env.sh <name>` を実行してスキャフォールドを生成
2. ユーザーの要件に応じて `profiles/<name>.env` の変数を埋める
3. 必要なオペレーターの Application YAML を `gitops/environments/<name>/apps/` に配置
4. 必要に応じて `gitops/environments/<name>/resources/` にカスタムリソースを追加
5. GPU が必要な場合は `GPU_MACHINE_TYPE` を設定し、NFD + NVIDIA Operator を含める
