# Changelog

## [Unreleased]

### Changed
- **すべての設定を環境変数で管理** (2025-11-14)
  - AWS認証情報をTerraform変数から環境変数に変更
  - リージョン、OCPバージョン、Billing Accountも環境変数化
  - `TF_VAR_*` プレフィックスでTerraform変数を自動認識
  - 機密情報を `env.sh` で一元管理
  - `terraform.tfvars` は最小限の設定のみ
  - よりセキュアで管理しやすい設定に改善

- **ROSA ログイン方法の更新** (2025-11-14)
  - 従来の `--token` フラグから新しい認証方式に変更
  - `rosa login --use-auth-code` (ブラウザ環境用)
  - `rosa login --use-device-code` (ブラウザレス環境用)
  - SSO認証を使用した対話型ログイン方式に対応

### Updated Files
- `env.sh` & `env.sh.example` - TF_VAR_* 環境変数を追加、レガシー変数も保持
- `terraform/versions.tf` - AWSプロバイダーから認証情報パラメータを削除
- `terraform/variables.tf` - AWS認証関連の変数定義を削除
- `terraform/terraform.tfvars.example` - 環境変数使用を前提とした最小限の設定に変更
- `terraform/README.md` (新規) - Terraform環境変数の詳細ドキュメント
- `README.md` - 環境変数による設定管理の説明を追加
- `QUICKSTART.md` - 環境変数ベースの設定手順に更新
- `deploy.sh` - 対話型ROSAログイン処理を追加、環境検出機能を実装
- `CHANGELOG.md` - 変更履歴を記録

## [1.0.0] - Initial Release

### Added
- Terraform設定ファイル一式
  - `versions.tf` - プロバイダー設定
  - `variables.tf` - 変数定義
  - `network.tf` - VPC/ネットワーク設定
  - `main.tf` - ROSA HCPクラスター設定
  - `outputs.tf` - 出力定義
- ドキュメント
  - `README.md` - 詳細ドキュメント
  - `QUICKSTART.md` - クイックスタートガイド
- 自動化スクリプト
  - `deploy.sh` - ワンコマンドデプロイスクリプト
  - `env.sh.example` - 環境変数設定サンプル
- Git設定
  - `.gitignore` - 機密情報の除外設定
- Ansible準備
  - `ansible/README.md` - 今後の実装計画

### Features
- AWS VPCの自動作成（パブリック/プライベートサブネット）
- ROSA HCPクラスターの自動デプロイ
- IAMロールとOIDCプロバイダーの自動設定
- クラスター管理者アカウントの自動作成
- Ansible連携用のJSON出力機能

