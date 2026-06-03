# Terraform State 確認レポート

実施日: 2025-03-03  
前提: すべてのリソースは解放済みの想定

---

## サマリ

| 対象 | リソース数 | 状態 |
|------|------------|------|
| **terraform/network** | **0** | ✅ 空（不要な残りなし） |
| **terraform/cluster** | **55** | ⚠️ 多数のエントリが残存（不要な残りの可能性大） |

---

## 1. Network State（問題なし）

- `terraform/network/terraform.tfstate` の `resources` は **空** (`[]`) です。
- リソース解放後、state もクリーンな状態です。

---

## 2. Cluster State（要対応）

### 2.1 残っているリソース数

- **55 件**のエントリが state に残っています。

### 2.2 State に記録されているアカウント情報

State 内のリソースはすべて **別アカウント** のものです。

| 項目 | State に記録されている値 |
|------|---------------------------|
| AWS Account ID | **916719129666** |
| IAM User | `open-environment-k566g-admin` |
| クラスター名 | `mta2` |

これが、現在の認証（例: 132787401659 / open-environment-jzhtw-admin）で `terraform plan` 等を実行すると **403 AccessDenied**（OIDC Provider 参照時）になる原因です。  
Terraform が「state に記録された 916719129666 のリソース」を refresh しようとし、現在のアカウントでは参照できないためです。

### 2.3 主な残存エントリの種類

- `data.aws_caller_identity.current`（ルート + モジュール内）
- `rhcs_hcp_machine_pool.worker_pool`（Worker プール）
- `module.rosa_hcp.*`
  - Account IAM（account roles, policy attachments）
  - **OIDC**: `aws_iam_openid_connect_provider.oidc_provider`（403 の直接原因）
  - Operator roles（8 本 + policy attachments）
  - ROSA HCP クラスター本体（`rhcs_cluster_rosa_hcp.rosa_hcp_cluster`）
  - Default ingress、data ソース、time_sleep、null_resource など

### 2.4 403 エラーとの対応

エラーに含まれる OIDC ARN:

```text
arn:aws:iam::916719129666:oidc-provider/oidc.op1.openshiftapps.com/2om2faupk0b05herar9dj87kbkvco2cu
```

上記は **cluster の state 内** の  
`module.rosa_hcp.module.oidc_config_and_provider[0].aws_iam_openid_connect_provider.oidc_provider`  
に同じ ARN として記録されています。  
→ 現在の認証でこの state を refresh すると、この OIDC 参照で 403 が発生します。

---

## 3. 推奨アクション（リソース解放済みの場合）

「すべてのリソースは解放している」前提であれば、cluster の state に残っている 55 件は **不要な残り** とみなせます。

### オプション A: State を空にして次回から新規作成する

リソースが本当に存在しない（または 916719129666 に戻れない）場合:

1. **state のバックアップ**  
   - `terraform/cluster/terraform.tfstate` および  
     `terraform/cluster/terraform.tfstate.backup*` を別ディレクトリにコピーして保管。

2. **state の削除（クリーンな状態からやり直す）**  
   - `terraform/cluster/terraform.tfstate` を削除（またはリネーム）。  
   - 必要に応じて `terraform.tfstate.backup*` も整理。  
   - 次回の `terraform plan` / `apply` は「リソースなし」として新規作成扱いになります。

### オプション B: State のみ手動でクリアする

`terraform state rm` で 55 件をすべて state から削除する方法もあります。  
（実リソースは変更されず、Terraform の管理対象から外れるだけです。）

- 例: `terraform state list` の出力をループで `terraform state rm <アドレス>` する。  
- モジュール配下は `module.rosa_hcp` ごと `state rm` するか、中身を一つずつ削除。

### 注意

- アカウント **916719129666** にまだクラスターや IAM リソースが残っている可能性がある場合は、**そのアカウントの認証**で `terraform destroy` を実行してから state を消す方が安全です。
- すでに 916719129666 にアクセスできない場合は、上記オプション A で state のみ削除し、現在のアカウントで新規にクラスターを立てる運用になります。

---

## 4. 参照: Cluster State 一覧（55 件）

```text
data.aws_caller_identity.current
rhcs_hcp_machine_pool.worker_pool
module.rosa_hcp.data.aws_caller_identity.current
module.rosa_hcp.null_resource.validations
module.rosa_hcp.module.account_iam_resources[0].data.aws_caller_identity.current
module.rosa_hcp.module.account_iam_resources[0].data.aws_iam_policy_document.custom_trust_policy[0]
module.rosa_hcp.module.account_iam_resources[0].data.aws_iam_policy_document.custom_trust_policy[1]
module.rosa_hcp.module.account_iam_resources[0].data.aws_iam_policy_document.custom_trust_policy[2]
module.rosa_hcp.module.account_iam_resources[0].data.aws_partition.current
module.rosa_hcp.module.account_iam_resources[0].data.rhcs_hcp_policies.all_policies
module.rosa_hcp.module.account_iam_resources[0].data.rhcs_info.current
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role.account_role[0]
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role.account_role[1]
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role.account_role[2]
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role_policy_attachment.account_role_policy_attachment[0]
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role_policy_attachment.account_role_policy_attachment[1]
module.rosa_hcp.module.account_iam_resources[0].aws_iam_role_policy_attachment.account_role_policy_attachment[2]
module.rosa_hcp.module.account_iam_resources[0].time_sleep.account_iam_resources_wait
module.rosa_hcp.module.oidc_config_and_provider[0].data.aws_region.current
module.rosa_hcp.module.oidc_config_and_provider[0].aws_iam_openid_connect_provider.oidc_provider
module.rosa_hcp.module.oidc_config_and_provider[0].null_resource.unmanaged_vars_validation
module.rosa_hcp.module.oidc_config_and_provider[0].rhcs_rosa_oidc_config.oidc_config
module.rosa_hcp.module.oidc_config_and_provider[0].time_sleep.wait_10_seconds
module.rosa_hcp.module.operator_roles[0].data.aws_caller_identity.current
module.rosa_hcp.module.operator_roles[0].data.aws_iam_policy_document.custom_trust_policy[0] … [7]
module.rosa_hcp.module.operator_roles[0].aws_iam_role.operator_role[0] … [7]
module.rosa_hcp.module.operator_roles[0].aws_iam_role_policy_attachment.operator_role_policy_attachment[0] … [7]
module.rosa_hcp.module.operator_roles[0].time_sleep.role_resources_propagation
module.rosa_hcp.module.rosa_cluster_hcp.data.aws_caller_identity.current[0]
module.rosa_hcp.module.rosa_cluster_hcp.data.aws_region.current[0]
module.rosa_hcp.module.rosa_cluster_hcp.data.aws_subnet.provided_subnet[0]
module.rosa_hcp.module.rosa_cluster_hcp.data.aws_subnet.provided_subnet[1]
module.rosa_hcp.module.rosa_cluster_hcp.rhcs_cluster_rosa_hcp.rosa_hcp_cluster
module.rosa_hcp.module.rosa_cluster_hcp.rhcs_hcp_default_ingress.default_ingress[0]
```

（上記は要約。実際の一覧は `terraform/cluster` で `terraform state list` を実行して確認してください。）
