# ai-serving 環境構築ノート

**目的**: LiteLLM vs MaaS Gateway の比較検証環境

RHOAI + RHCL + LiteLLM のモデルサービング環境。構築時に遭遇した考慮点を記録する。

## コンポーネント構成

| コンポーネント | バージョン / チャネル | 備考 |
|---|---|---|
| OCP (ROSA HCP) | 4.22.x | クラスター名: ai-srv（32文字制限対応） |
| RHOAI | 3.4.2 (stable-3.x) | fast-3.x は 3.3.1 止まりなので注意 |
| RHCL | 1.4.1 (stable) | MaaS / TokenRateLimitPolicy に必須 |
| cert-manager | stable-v1 | RHOAI 3.x + RHCL の共通依存 |
| NFD Operator | - | GPU ノード検出用 |
| NVIDIA GPU Operator | - | GPU ドライバ・ランタイム |
| LiteLLM | main-latest (non_root) | AI Gateway（比較対象） |
| PostgreSQL | 16 (RHEL9) | LiteLLM のバックエンド DB |
| Granite 3.3 2B | ModelCar OCI | テスト用モデル（g6.xlarge 16GB VRAM 対応） |

## ArgoCD Application 構成

```
sync-wave  0: cert-manager, nfd-operator, nvidia-operator
sync-wave  5: openshift-ai-operator, rhcl-operator
sync-wave 10: openshift-ai-config (DSC)
sync-wave 15: model-serving, litellm
sync-wave 20: openshift-ai-post (AcceleratorProfile)
```

## DSC の MaaS 設定

`kserve.modelsAsService.managementState: Managed` を設定。
RHCL (Kuadrant) がインストールされていないと Warning が出るが、
RHCL インストール後に自動的に連携される。

## RHOAI チャネル選択

RHOAI 3.x では **`fast-3.x` は最新ではない**。

```
fast-3.x   → 3.3.1（更新が止まっている）
stable-3.x → 3.4.2（最新 GA を追従）
stable-3.4 → 3.4.2（特定バージョン固定）
```

3.4 を使う場合は `stable-3.x` または `stable-3.4` を指定する。

## DSC (DataScienceCluster) の注意点

### kserve.serving フィールドは 3.x に存在しない

RHOAI 2.x の DSC には `kserve.serving`（Knative Serving 制御）があったが、
3.x では削除されている。古い DSC テンプレートをそのまま使うとスキーマエラーになる。

```
failed to create typed patch object: .spec.components.kserve.serving: field not declared in schema
```

### kueue: Managed は Webhook で拒否される

CRD スキーマ上は `Managed | Unmanaged | Removed` の3値だが、
3.4 の admission webhook は `Managed` を拒否する。

```
admission webhook denied the request: Managed is no longer supported as a managementState
```

RHOAI 3.4 では Kueue は **別途 Kueue Operator のインストールが前提**。
モデルサービングだけなら `Removed` でよい。バッチ推論が必要なら Kueue Operator を追加する。

### AcceleratorProfile CRD は Dashboard 起動後に作成される

`AcceleratorProfile` (`dashboard.opendatahub.io/v1`) は RHOAI Operator 自体の CRD ではなく、
DSC の Dashboard コンポーネントが起動した後に登録される。
Operator インストール直後に適用しようとすると `no matches for kind` エラーになる。

## ArgoCD 構成: 3段階分離

Operator CRD 依存リソースを同一 Application にすると、CRD 未登録で sync 失敗する。
以下の3段構成で解決した。

```
sync-wave 0:  openshift-ai-operator   — Namespace, OperatorGroup, Subscription
sync-wave 10: openshift-ai-config     — DataScienceCluster（Operator CRD に依存）
sync-wave 20: openshift-ai-post       — AcceleratorProfile（Dashboard CRD に依存）
```

各 Application に `retry` を設定し、CRD 登録待ちを自動リトライで吸収する。

### ArgoCD キャッシュの罠

repo-server のキャッシュが残ると、Git 更新後も古いマニフェストで sync される。
`hard refresh` アノテーションだけでは解消しないケースがある。

**対処**: repo-server Pod を再起動してキャッシュをクリアする。

```bash
oc delete pod -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-repo-server
```

## LiteLLM

### PostgreSQL が必須

LiteLLM は DB 接続なしでは起動しない。`DATABASE_URL` 環境変数が必要。

```
postgresql://litellm:<password>@litellm-postgresql:5432/litellm
```

### メモリ要件

`limits.memory: 1Gi` では OOMKilled になる。**2Gi 以上**を推奨。

```yaml
resources:
  requests:
    memory: 1Gi
  limits:
    memory: 2Gi
```

### OpenShift SCC 対応

標準の LiteLLM イメージは root で動作するため OpenShift の restricted SCC に引っかかる。
**non_root イメージ**を使う。

```
ghcr.io/berriai/litellm-non_root:main-latest
```

## ROSA HCP 固有

### operator_role_prefix の 32 文字制限

ROSA HCP では `operator_role_prefix` が `{ユーザー名}-{クラスター名}-operator-roles` の形式で
自動生成され、**32 文字以内**でなければならない。

```
hkaneko-ai-serving-operator-roles  → 33文字 ❌
hkaneko-ai-srv-operator-roles      → 30文字 ✅
```

クラスター名は短くする。既存クラスターがある場合は **destroy してから名前を変更**する
（IAM ロール名が変わるため）。
