#!/bin/bash

###############################################################################
# MTA for Developer Lightspeed ワークショップ環境構築スクリプト
# 
# このスクリプトは以下を実行します：
# 1. Terraformを使用してROSA HCPクラスターを構築
###############################################################################

set -e  # エラーが発生したら即座に終了

# カラー出力の設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# バナー表示
print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║  MTA for Developer Lightspeed Workshop Environment          ║
║  Red Hat OpenShift for AWS (ROSA) Cluster Setup              ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 必要なツールの確認
check_prerequisites() {
    log_info "必要なツールの確認中..."
    
    local missing_tools=()
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v rosa &> /dev/null; then
        missing_tools+=("rosa-cli")
    fi
    
    if ! command -v oc &> /dev/null; then
        missing_tools+=("openshift-cli (oc)")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "以下のツールがインストールされていません："
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        log_info "インストール方法："
        echo "  brew install terraform awscli rosa-cli openshift-cli"
        exit 1
    fi
    
    log_success "すべての必要なツールが確認されました"
}

# 環境変数の確認
check_environment() {
    log_info "環境変数の確認中..."
    
    local missing_vars=()
    
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        missing_vars+=("AWS_ACCESS_KEY_ID")
    fi
    
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY")
    fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "以下の環境変数が設定されていません："
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        log_info "環境変数を設定してください："
        echo "  export AWS_ACCESS_KEY_ID=your_access_key"
        echo "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
        exit 1
    fi
    
    log_success "環境変数が確認されました"
}

# ROSA CLIのログイン
rosa_login() {
    log_info "ROSA CLIへのログイン..."
    
    # 既にログインしているか確認
    if rosa whoami > /dev/null 2>&1; then
        log_success "ROSAに既にログイン済みです"
    else
        log_warning "ROSAへのログインが必要です"
        echo ""
        echo "以下のいずれかのコマンドでログインしてください："
        echo ""
        echo "  オプション1 (ブラウザ環境の場合):"
        echo "    rosa login --use-auth-code"
        echo ""
        echo "  オプション2 (ブラウザレス環境の場合):"
        echo "    rosa login --use-device-code"
        echo ""
        read -p "ログインを実行しますか？ (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            # ブラウザが利用可能か確認
            if [ -n "$DISPLAY" ] || [[ "$OSTYPE" == "darwin"* ]]; then
                log_info "ブラウザ環境を検出しました。auth-codeを使用します..."
                rosa login --use-auth-code
            else
                log_info "ブラウザレス環境を検出しました。device-codeを使用します..."
                rosa login --use-device-code
            fi
            
            if rosa whoami > /dev/null 2>&1; then
                log_success "ROSAにログインしました"
            else
                log_error "ROSAへのログインに失敗しました"
                exit 1
            fi
        else
            log_error "ROSAログインがキャンセルされました"
            exit 1
        fi
    fi
    
    log_info "AWSパーミッションの確認中..."
    rosa verify permissions --region "${AWS_DEFAULT_REGION:-ap-northeast-1}"
    
    log_info "AWSクォータの確認中..."
    rosa verify quota --region "${AWS_DEFAULT_REGION:-ap-northeast-1}"

    log_info "Terraform 用の RHCS 認証は環境変数から行われます。"
    log_info "推奨: サービスアカウントの RHCS_CLIENT_ID / RHCS_CLIENT_SECRET を env.sh に設定してください。"
}

# フェーズ1: ネットワークのデプロイ
deploy_network() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ1: ネットワークリソースの構築"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd terraform/network
    
    # terraform.tfvarsが存在しない場合は作成を促す
    if [ ! -f "terraform.tfvars" ]; then
        log_warning "terraform.tfvarsが存在しません"
        log_info "terraform.tfvars.exampleからコピーして設定してください"
        cp terraform.tfvars.example terraform.tfvars
        log_error "terraform.tfvarsを編集してから再度実行してください"
        cd ../..
        exit 1
    fi
    
    # Terraform初期化
    log_info "Terraformの初期化中..."
    terraform init
    
    # Terraform実行計画
    log_info "Terraform実行計画の作成中..."
    terraform plan -out=tfplan
    
    # Terraform適用
    log_info "Terraformを適用中..."
    terraform apply tfplan
    
    log_success "ネットワークリソースの構築が完了しました！"
    
    # ネットワーク情報を出力
    echo ""
    log_info "==== ネットワーク情報 ===="
    echo "VPC ID: $(terraform output -raw vpc_id)"
    echo "VPC CIDR: $(terraform output -raw vpc_cidr)"
    echo "Public Subnets: $(terraform output -json public_subnet_ids | jq -r 'join(", ")')"
    echo "Private Subnets: $(terraform output -json private_subnet_ids | jq -r 'join(", ")')"
    
    cd ../..
}

# フェーズ2: ROSAクラスターのデプロイ
deploy_cluster() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ2: ROSAクラスターの構築"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd terraform/cluster
    
    # ネットワークモジュールの出力を取得
    log_info "ネットワークモジュールの出力を取得中..."
    cd ../network
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    VPC_CIDR=$(terraform output -raw vpc_cidr 2>/dev/null || echo "")
    
    # jqが利用可能か確認
    if command -v jq > /dev/null 2>&1; then
        PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids 2>/dev/null | jq -r 'join(",")' || echo "")
        PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || echo "")
        AVAILABILITY_ZONES=$(terraform output -json availability_zones 2>/dev/null | jq -r 'join(",")' || echo "")
    else
        # jqが利用できない場合、手動でパース
        log_warning "jqが利用できません。手動でパースします..."
        PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
        PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
        AVAILABILITY_ZONES=$(terraform output -json availability_zones 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
    fi
    
    if [ -z "$VPC_ID" ] || [ -z "$PUBLIC_SUBNET_IDS" ] || [ -z "$PRIVATE_SUBNET_IDS" ]; then
        log_error "ネットワークモジュールの出力を取得できませんでした"
        log_error "先にネットワークモジュールをデプロイしてください"
        cd ../..
        exit 1
    fi
    
    cd ../cluster
    
    # terraform.tfvarsが存在しない場合は作成
    if [ ! -f "terraform.tfvars" ]; then
        log_info "terraform.tfvarsを作成中..."
        cp terraform.tfvars.example terraform.tfvars
    fi
    
    # ネットワーク情報をterraform.tfvarsに設定/更新
    log_info "ネットワーク情報をterraform.tfvarsに設定中..."
    
    # 一時ファイルを作成して更新
    TMP_FILE=$(mktemp)
    cat terraform.tfvars > "$TMP_FILE"
    
    # 既存のネットワーク設定を削除
    sed -i.bak '/^# Network outputs/,/^availability_zones/d' "$TMP_FILE" 2>/dev/null || true
    sed -i.bak '/^vpc_id/d' "$TMP_FILE" 2>/dev/null || true
    sed -i.bak '/^public_subnet_ids/d' "$TMP_FILE" 2>/dev/null || true
    sed -i.bak '/^private_subnet_ids/d' "$TMP_FILE" 2>/dev/null || true
    sed -i.bak '/^availability_zones/d' "$TMP_FILE" 2>/dev/null || true
    
    # ネットワーク情報を追加
    cat >> "$TMP_FILE" << EOF

# Network outputs (automatically set from network module)
vpc_id             = "${VPC_ID}"
public_subnet_ids  = ["$(echo "$PUBLIC_SUBNET_IDS" | sed 's/,/", "/g')"]
private_subnet_ids = ["$(echo "$PRIVATE_SUBNET_IDS" | sed 's/,/", "/g')"]
availability_zones = ["$(echo "$AVAILABILITY_ZONES" | sed 's/,/", "/g')"]
EOF
    
    mv "$TMP_FILE" terraform.tfvars
    rm -f terraform.tfvars.bak 2>/dev/null || true
    
    # Terraform初期化
    log_info "Terraformの初期化中..."
    terraform init
    
    # Terraform実行計画
    log_info "Terraform実行計画の作成中..."
    terraform plan -out=tfplan
    
    # Terraform適用
    log_info "Terraformを適用中（時間がかかります）..."
    terraform apply tfplan
    
    log_success "Terraformによるデプロイリクエストが送信されました！"
    log_info "注意: wait_for_create_complete = false のため、Terraformは即座に完了します"
    log_info "次のステップで rosa logs install でクラスター構築の進行状況を監視します"
    echo ""
    
    # 出力情報の表示（クラスターIDが利用可能な場合）
    echo ""
    log_info "==== クラスター情報 ===="
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "N/A")
    CLUSTER_ID=$(terraform output -raw cluster_id 2>/dev/null || echo "N/A")
    echo "クラスター名: ${CLUSTER_NAME}"
    echo "クラスターID: ${CLUSTER_ID}"
    
    if [ "$CLUSTER_ID" != "N/A" ]; then
        echo "API URL: $(terraform output -raw cluster_api_url 2>/dev/null || echo "準備中...")"
        echo "Console URL: $(terraform output -raw cluster_console_url 2>/dev/null || echo "準備中...")"
    else
        echo "API URL: 準備中..."
        echo "Console URL: 準備中..."
    fi
    
    echo ""
    log_info "クラスターが準備できたら、以下でログインできます："
    echo "  oc login <API_URL> -u <USER> -p <PASSWORD>"
    echo ""
    log_warning "管理者パスワードを確認するには以下を実行してください："
    echo "  cd terraform/cluster && terraform output cluster_admin_password"
    
    # Ansible用のクラスター情報を保存
    log_info "Ansible用のクラスター情報を保存中..."
    mkdir -p ../../ansible
    terraform output -json ansible_inventory_json > ../../ansible/cluster_info.json
    
    cd ../..
}

# クラスター構築のログを監視して完了を待つ
wait_for_cluster_ready() {
    log_info "クラスター構築の進行状況を監視します..."
    
    cd terraform/cluster
    
    # クラスター名を取得
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    if [ -z "$CLUSTER_NAME" ] || [ "$CLUSTER_NAME" = "N/A" ]; then
        log_warning "クラスター名を取得できませんでした"
        cd ../..
        return 1
    fi
    
    cd ../..
    
    log_info "クラスター名: ${CLUSTER_NAME}"
    log_info "rosa logs install で構築ログを監視します..."
    echo ""
    log_warning "注意: クラスター構築には約30-40分かかります"
    echo ""
    
    # rosa logs install --watch でログを監視
    # このコマンドはクラスター構築が完了するまで待機します
    if rosa logs install -c "${CLUSTER_NAME}" --watch; then
        log_success "クラスター構築が完了しました！"
        return 0
    else
        log_error "クラスター構築の監視中にエラーが発生しました"
        return 1
    fi
}

# クラスターへのログイン確認
verify_cluster_access() {
    log_info "クラスターへのアクセスを確認中..."
    
    cd terraform/cluster
    
    CLUSTER_API=$(terraform output -raw cluster_api_url 2>/dev/null || echo "")
    ADMIN_USER=$(terraform output -raw cluster_admin_username 2>/dev/null || echo "")
    ADMIN_PASS=$(terraform output -raw cluster_admin_password 2>/dev/null || echo "")
    cd ../..
    
    if [ -z "$CLUSTER_API" ] || [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
        log_warning "クラスター情報がまだ利用できません"
        return 1
    fi
    
    if oc login "${CLUSTER_API}" -u "${ADMIN_USER}" -p "${ADMIN_PASS}" --insecure-skip-tls-verify 2>/dev/null; then
        log_success "クラスターにログインしました"
        
        echo ""
        log_info "==== ノード情報 ===="
        oc get nodes
        
        echo ""
        log_info "==== クラスターバージョン ===="
        oc get clusterversion
        return 0
    else
        log_error "クラスターへのログインに失敗しました"
        return 1
    fi
}

# メイン処理
main() {
    print_banner
    
    # ステップ1: 前提条件の確認
    check_prerequisites
    check_environment
    
    # ステップ2: ROSAの準備
    rosa_login
    
    # ステップ3: フェーズ1 - ネットワークリソースの構築
    deploy_network
    
    # ステップ4: フェーズ2 - ROSAクラスターの構築
    deploy_cluster
    
    # ステップ5: クラスター構築の完了を待つ（rosa logs install --watch）
    log_info "Terraformはクラスター作成リクエストを送信しました"
    log_info "rosa logs install でクラスター構築の進行状況を監視します..."
    wait_for_cluster_ready
    
    # ステップ6: クラスターアクセス確認
    verify_cluster_access
    
    # 完了メッセージ
    echo ""
    log_success "======================================"
    log_success "  環境構築が完了しました！"
    log_success "======================================"
    echo ""
    log_info "次のステップ："
    echo "  1. クラスターにログイン"
    echo "     oc login <API_URL> -u cluster-admin -p <PASSWORD>"
    echo ""
    echo "  2. OpenShift Consoleにアクセス"
    echo "     上記のConsole URLをブラウザで開いてください"
    echo ""
}

# スクリプト実行
main "$@"

