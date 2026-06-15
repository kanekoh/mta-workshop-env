# openshift-ai Environment - ArgoCD Applications

このディレクトリに ArgoCD Application YAML を配置すると、
App-of-Apps パターンで自動的にデプロイされます。

## 利用可能なオペレーター

以下から必要なものを `gitops/environments/mta/apps/` 等からコピーしてください:

| ファイル | オペレーター | 用途 |
|---------|------------|------|
| nfd-operator.yml | Node Feature Discovery | GPU ノード検出（GPU 使用時必須） |
| nvidia-operator.yml | NVIDIA GPU Operator | GPU ドライバー管理 |
| openshift-ai-operator.yml | OpenShift AI (RHOAI) | AI/ML プラットフォーム |
| authorino-operator.yml | Authorino | API 認証 |
| devspaces-operator.yml | Dev Spaces | クラウド IDE |
| cnpg-operator.yml | CloudNativePG | PostgreSQL |
| keycloak-operator.yml | Keycloak | ID 管理 |
| mta-operator.yml | MTA | アプリ移行ツール |
| loki-operator.yml | Loki | ログ収集 |
| network-observability-operator.yml | Network Observability | ネットワーク可視化 |

## Cursor AI での追加

Cursor に以下のように依頼できます:

  「openshift-ai 環境に DevSpaces と Keycloak を追加して」

