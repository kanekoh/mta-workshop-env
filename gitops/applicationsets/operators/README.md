# Operator ApplicationSet

このApplicationSetは、すべてのOperatorをArgoCDで管理するために使用されます。

## 概要

ApplicationSetのList Generatorを使用して、各Operator用のApplicationを動的に生成します。RoleARNが必要なOperator（DevSpaces等）については、Helm Chartを使用してConfigMapからRoleARNを注入します。

## 使用方法

このApplicationSetは、ArgoCDのapp-of-appsパターンで自動的に検出されるか、手動で適用できます：

```bash
oc apply -f gitops/applicationsets/operators/operators-applicationset.yaml
```

## 管理されるOperator

- NFD Operator
- NVIDIA GPU Operator
- OpenShift AI Operator
- Authorino Operator
- DevSpaces Operator (RoleARNが必要)
- Cloud Native PostgreSQL Operator
- Red Hat build of Keycloak Operator

## RoleARNの設定

RoleARNが必要なOperator（DevSpaces等）については、`operator-rolearns` ConfigMapにRoleARNを設定する必要があります。このConfigMapはAnsible playbook (`setup_operator_configmaps.yml`) で自動的に作成されます。

ConfigMapの形式：
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: operator-rolearns
  namespace: openshift-gitops
data:
  devspaces-rolearn: "arn:aws:iam::ACCOUNT_ID:user/IAM_USER_NAME"
```

## Helm Chartの使用

RoleARNが必要なOperatorは、Helm Chartを使用してSubscriptionテンプレートにRoleARNを注入します。各Operatorディレクトリに`Chart.yaml`と`values.yaml`、`templates/`ディレクトリが必要です。

