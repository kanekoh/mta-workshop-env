# Ansible Configuration for OpenShift Post-Deployment

このディレクトリには、Terraformで構築したROSAクラスターに対して追加の設定を行うためのAnsible playbookが含まれます。

## 実装済み機能

### 1. OpenShift GitOps Operatorのインストール
- OpenShift GitOps Operatorのインストール
- Operatorの準備完了を待機

**注意**: ArgoCD Application/AppProjectの作成は別途実施してください。

## ディレクトリ構造

```
ansible/
├── README.md                    # このファイル
├── ansible.cfg                  # Ansible設定
├── requirements.yml             # Ansible Galaxy requirements
├── cluster_info.json            # Terraformから取得したクラスター情報
├── inventory/
│   ├── hosts.yml               # インベントリファイル
│   └── group_vars/
│       └── all.yml             # 共通変数（GitOps設定含む）
├── playbooks/
│   ├── site.yml                # メインplaybook
│   └── install_gitops.yml      # OpenShift GitOps設定playbook
└── roles/
    └── openshift_gitops/       # OpenShift GitOps設定ロール
        ├── defaults/
        │   └── main.yml        # デフォルト変数
        ├── vars/
        │   └── main.yml        # ロール変数
        ├── tasks/
        │   ├── main.yml        # メインタスク
        │   ├── install_operator.yml  # Operatorインストール
        │   └── wait_operator.yml     # Operator待機
```

## 前提条件

```bash
# Ansible のインストール
brew install ansible

# OpenShift コレクションのインストール
ansible-galaxy collection install -r requirements.yml
```

## 設定方法

### Operator設定

`inventory/group_vars/all.yml` でOperatorの設定を確認・変更できます：

```yaml
openshift_gitops:
  operator_namespace: openshift-gitops-operator
  operator_name: openshift-gitops-operator
  operator_channel: latest
  operator_source: redhat-operators
```

## 使用方法

### 1. クラスターへのログイン

```bash
# クラスターにログイン
oc login <API_URL> -u <USER> -p <PASSWORD>
```

### 2. Ansible playbook の実行

```bash
cd ansible

# メインplaybookを実行
ansible-playbook playbooks/site.yml

# または、GitOpsのみインストール
ansible-playbook playbooks/install_gitops.yml
```

### 3. 実行結果の確認

```bash
# OpenShift GitOps Operatorの状態確認
oc get subscription -n openshift-gitops-operator | grep gitops

# CSVの状態確認
oc get csv -n openshift-gitops-operator | grep gitops

# ArgoCDインスタンスの確認（Operatorインストール後）
oc get argocd -n openshift-gitops
```

## 変数説明

### OpenShift GitOps設定

| 変数名 | 説明 | デフォルト値 |
|--------|------|--------------|
| `openshift_gitops.operator_namespace` | OperatorをインストールするNamespace | `openshift-gitops-operator` |
| `openshift_gitops.operator_name` | Operator名 | `openshift-gitops-operator` |
| `openshift_gitops.operator_channel` | Operatorチャネル | `latest` |
| `openshift_gitops.operator_source` | Operatorソース | `redhat-operators` |
| `openshift_gitops.argocd_namespace` | ArgoCDインスタンスのNamespace（参考） | `openshift-gitops` |

## トラブルシューティング

### Operatorがインストールされない

```bash
# CSVの状態を確認
oc get csv -n openshift-gitops-operator | grep gitops

# Subscriptionの詳細を確認
oc describe subscription openshift-gitops-operator -n openshift-gitops-operator

# InstallPlanの状態を確認
oc get installplan -n openshift-gitops-operator
```

## 参考リンク

- [Ansible Documentation](https://docs.ansible.com/)
- [OpenShift Ansible Collection](https://docs.ansible.com/ansible/latest/collections/community/okd/)
- [Kubernetes Ansible Collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)
- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
