# Profiles

環境プロファイルの一覧と、各プロファイル固有の手順。

## プロファイル一覧

| プロファイル | 用途 | 主要コンポーネント |
|-------------|------|-------------------|
| `mta-full.env` | MTA ワークショップ（フル） | MTA Operator, Tackle |
| `mta-light.env` | MTA ワークショップ（軽量） | MTA Operator |
| `openshift-ai.env` | OpenShift AI 検証 | RHOAI, GPU Operator, NFD |
| `ai-serving.env` | AI モデルサービング | RHOAI, GPU, KServe |
| `observability.env` | 可観測性デモ | Logging, Monitoring |
| `mce-odf.env` | MCE + ODF + HCP | Multicluster Engine, ODF, Hosted Control Planes |
| `custom-example.env` | テンプレート | カスタマイズ用 |

## 使い方

```bash
# プロファイルを指定してデプロイ
export PROFILE=mce-odf
./deploy.sh

# 削除
export PROFILE=mce-odf
./destroy.sh
```

---

## mce-odf プロファイル: HCP クラスター作成手順

`mce-odf` プロファイルでは、ROSA 上に MCE + ODF を構築し、
さらに Hosted Control Plane (HCP) で Self-Managed の OCP クラスターを作成できます。

### 前提条件

- ROSA クラスターに MCE operator がインストール済み（`hypershift` / `hypershift-local-hosting` 有効）
- `oc` CLI でホスティングクラスターにログイン済み
- `env.sh` に AWS 認証情報が設定済み
- Pull Secret を配置済み

### 1. hcp CLI のインストール

MCE がインストールされると `ConsoleCLIDownload` リソースからダウンロードできます。

```bash
# ダウンロード URL を取得
oc get ConsoleCLIDownload hcp-cli-download -o jsonpath='{.spec.links[0].href}'

# ダウンロード＆配置 (macOS ARM の例)
curl -ko hcp.tar.gz https://hcp-cli-download-multicluster-engine.apps.<cluster-domain>/darwin/arm64/hcp.tar.gz
tar xfz hcp.tar.gz
sudo mv hcp /usr/local/bin/
```

### 2. Pull Secret の配置

https://console.redhat.com/openshift/install/pull-secret からダウンロード：

```bash
cp ~/Downloads/pull-secret.txt ./pull-secret.txt
```

### 3. 環境変数の設定

```bash
export HCP_CLUSTER_NAME="my-hosted"
export HCP_BASE_DOMAIN="sandbox1863.opentlc.com"
```

> **Tip**: `HCP_BASE_DOMAIN` には Red Hat Demo Platform の `aws_route53_domain` を利用すると
> DNS 委任が不要で扱いやすい。

オプション変数：

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `HCP_REGION` | env.sh の `AWS_DEFAULT_REGION` | AWS リージョン |
| `HCP_NODE_REPLICAS` | 2 | Worker ノード数 |
| `HCP_RELEASE_IMAGE` | 最新 | OCP リリースイメージ |
| `HCP_PULL_SECRET` | `./pull-secret.txt` | Pull Secret パス |
| `HCP_NAMESPACE` | `clusters` | HostedCluster の namespace |

### 4. AWS リソース事前準備

```bash
./scripts/hcp-create-cluster.sh prepare
```

以下を作成します：
- S3 バケット（OIDC 用）
- IAM ロール
- STS credentials ファイル
- クラスター上に OIDC Secret

### 5. Hosted Cluster 作成

```bash
./scripts/hcp-create-cluster.sh create
```

### 6. 状態確認

```bash
./scripts/hcp-create-cluster.sh status

# 詳細
oc -n clusters get hostedcluster -w
oc -n clusters get nodepool -w
```

### 7. Hosted Cluster へのアクセス

```bash
# kubeconfig 取得
oc extract secret/${HCP_CLUSTER_NAME}-admin-kubeconfig -n clusters --to=- > my-hosted.kubeconfig

# 接続確認
oc --kubeconfig=my-hosted.kubeconfig get nodes
oc --kubeconfig=my-hosted.kubeconfig get co
```

### 8. 削除

```bash
./scripts/hcp-create-cluster.sh destroy
```

クラスター、AWS インフラ（VPC、IAM ロール等）、S3 バケットをすべてクリーンアップします。

### クイックリファレンス

```bash
# 全体フロー
export HCP_CLUSTER_NAME="my-hosted"
export HCP_BASE_DOMAIN="sandbox1863.opentlc.com"

./scripts/hcp-create-cluster.sh prepare   # AWS リソース準備
./scripts/hcp-create-cluster.sh create    # クラスター作成
./scripts/hcp-create-cluster.sh status    # 状態確認
./scripts/hcp-create-cluster.sh destroy   # 削除
```
