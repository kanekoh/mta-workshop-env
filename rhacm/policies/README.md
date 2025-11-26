# RHACM PolicyGeneratorによるOperator管理

このディレクトリには、Red Hat Advanced Cluster Management (RHACM) のPolicyGeneratorを使用してOperatorを管理するための定義が含まれています。

## 概要

RHACMのPolicyGeneratorを使用して、すべてのOperatorのインストールと管理を行います。これにより、インフラレベルのOperatorを一元管理できます。

## ディレクトリ構造

```
rhacm/
├── policies/
│   ├── operators/          # PolicyGenerator定義
│   └── README.md          # このファイル
└── manifests/
    └── operators/         # Operatorマニフェスト（Namespace, OperatorGroup, Subscription, CR等）
```

## PolicyGeneratorの仕組み

PolicyGeneratorは、Gitリポジトリ内のマニフェストを参照して、Policyリソースを自動生成します。各PolicyGenerator定義は以下の要素を含みます：

- **placement**: どのクラスターに適用するか（通常は`local-cluster`）
- **policies**: 生成するPolicyのリスト
- **manifestConfigs**: 参照するマニフェストのパス

## 使用方法

1. **マニフェストの配置**: `rhacm/manifests/operators/{operator-name}/` にOperatorのマニフェストを配置

2. **PolicyGenerator定義の作成**: `rhacm/policies/operators/{operator-name}-policygenerator.yaml` を作成

3. **PolicyGeneratorの適用**: Ansible playbook実行時に自動的に適用されます

## 管理されるOperator

以下のOperatorがRHACMで管理されます：

- NFD Operator
- NVIDIA GPU Operator
- OpenShift AI Operator
- Authorino Operator
- DevSpaces Operator
- Cloud Native PostgreSQL Operator
- Red Hat build of Keycloak Operator

## 注意事項

- PolicyGeneratorはGitリポジトリからマニフェストを取得するため、正しいパスを設定する必要があります
- マニフェスト内のArgoCDアノテーション（`argocd.argoproj.io/*`）は削除してください（RHACMでは不要）
- DevSpacesのAWS Role ARNなど、動的な値が必要な場合は、ConfigMapやSecretを使用するか、deploy.shで事前に置換してください

