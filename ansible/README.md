# Ansible Configuration for OpenShift Post-Deployment

このディレクトリには、Terraformで構築したROSAクラスターに対して追加の設定を行うためのAnsible playbookが含まれます。

## 実装予定の機能

### 1. Identity Provider (IDP) 設定
- htpasswdベースの認証設定
- ワークショップユーザーの作成（user1-user60）
- 管理ユーザー（wkadmin）の設定

### 2. ArgoCD のインストールと設定
- OpenShift GitOps Operatorのインストール
- ArgoCD インスタンスの作成
- RBAC設定

### 3. ワークショップ環境の準備
- プロジェクト/Namespaceの作成
- リソースクォータの設定
- ネットワークポリシーの設定

### 4. Konveyor AI 関連のセットアップ
- 必要なOperatorのインストール
- 開発環境の準備

## ディレクトリ構造（予定）

```
ansible/
├── README.md                    # このファイル
├── ansible.cfg                  # Ansible設定
├── inventory/
│   ├── hosts.yml               # インベントリファイル
│   └── group_vars/
│       └── all.yml             # 共通変数
├── playbooks/
│   ├── site.yml                # メインplaybook
│   ├── configure_idp.yml       # IDP設定
│   ├── install_argocd.yml      # ArgoCD設定
│   └── setup_workshop.yml      # ワークショップ環境設定
├── roles/
│   ├── openshift_idp/          # IDP設定ロール
│   ├── openshift_gitops/       # ArgoCD設定ロール
│   └── workshop_setup/         # ワークショップ準備ロール
└── files/
    └── htpasswd/               # htpasswdファイル

```

## 使用方法（準備中）

### 前提条件

```bash
# Ansible のインストール
brew install ansible

# OpenShift コレクションのインストール
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install community.okd
```

### 実行手順

1. Terraformからクラスター情報を取得（自動）
```bash
# deploy.sh スクリプトが自動的に実行します
# または手動で：
cd terraform
terraform output -json ansible_inventory_json > ../ansible/cluster_info.json
```

2. Ansible playbook の実行
```bash
cd ansible
ansible-playbook playbooks/site.yml
```

## 今後の実装

- [ ] ansible.cfg の作成
- [ ] インベントリファイルの作成
- [ ] IDP設定playbook
- [ ] ArgoCD設定playbook
- [ ] ワークショップ環境セットアップplaybook
- [ ] htpasswdユーザー生成スクリプト

## 参考リンク

- [Ansible Documentation](https://docs.ansible.com/)
- [OpenShift Ansible Collection](https://docs.ansible.com/ansible/latest/collections/community/okd/)
- [Kubernetes Ansible Collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)

