# MTA環境専用リソース

このディレクトリには、MTA環境専用のリソースを配置します。

## ディレクトリ構造

```
resources/
├── configmaps/          # ConfigMapリソース
├── secrets/             # Secretリソース（注意: 機密情報を含む）
└── custom-resources/    # カスタムリソース（CRD）
```

## 使用方法

### 1. Application定義で参照

環境専用リソースをデプロイする場合は、`gitops/environments/mta/apps/` にApplication定義を作成し、以下のようにpathを指定します：

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

### 2. リソースの配置例

#### ConfigMapの例

`configmaps/app-config.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: your-namespace
data:
  config.yaml: |
    key: value
```

#### カスタムリソースの例

`custom-resources/keycloak-realm.yaml`:
```yaml
apiVersion: keycloak.org/v1alpha1
kind: KeycloakRealm
metadata:
  name: mta-realm
  namespace: keycloak-operator
spec:
  # ...
```

## 注意事項

- **Secrets**: 機密情報を含むため、Gitにコミットする場合は暗号化を検討してください
- **Namespace**: 各リソースに適切なnamespaceを指定してください
- **Sync-wave**: 必要に応じて `argocd.argoproj.io/sync-wave` アノテーションを使用してデプロイ順序を制御してください

