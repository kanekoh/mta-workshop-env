#!/bin/bash

###############################################################################
# MTA for Developer Lightspeed ワークショップ環境構築スクリプト
# 
# このスクリプトは以下を実行します：
# 1. Terraformを使用してROSA HCPクラスターを構築
#
# オプション:
#   --log-file <file>    ログを指定ファイルに出力
#   -l, --log            ログをデフォルトファイル名で出力（deploy-YYYYMMDD-HHMMSS.log）
#   -h, --help           ヘルプを表示
#
# 環境変数:
#   DEPLOY_LOG_FILE      ログファイルパス（--log-fileオプションで上書き可能）
###############################################################################

# スクリプトのディレクトリを取得（プロジェクトルートに移動）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ログファイル設定（環境変数から読み込み）
LOG_FILE="${DEPLOY_LOG_FILE:-}"
FORCE_DEPLOY=false

# オプション解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -l|--log)
            if [ -z "$LOG_FILE" ]; then
                LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"
            fi
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --log-file <file>    Log output to specified file
  -l, --log            Log output to default file (deploy-YYYYMMDD-HHMMSS.log)
  --force              Force deployment even if resources already exist
  -h, --help           Show this help message

Environment Variables:
  DEPLOY_LOG_FILE      Log file path (overridden by --log-file option)

Examples:
  $0 --log
  $0 --log-file my-deploy.log
  $0 --force
  DEPLOY_LOG_FILE=deploy.log $0
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage information" >&2
            exit 1
            ;;
    esac
done

# ログファイルが指定されている場合、teeで出力をリダイレクト
if [ -n "$LOG_FILE" ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "ログファイル: $LOG_FILE"
    echo "開始時刻: $(date)"
    echo "========================================"
fi

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
║  MTA for Developer Lightspeed Workshop Environment            ║
║  Red Hat OpenShift for AWS (ROSA) Cluster Setup               ║
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
    
    if ! command -v ansible-playbook &> /dev/null; then
        missing_tools+=("ansible")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "以下のツールがインストールされていません："
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        log_info "インストール方法："
        echo "  brew install terraform awscli rosa-cli openshift-cli ansible"
        exit 1
    fi
    
    log_success "すべての必要なツールが確認されました"
}

# env.shの自動読み込み（条件付き）
load_env_if_needed() {
    if [ -f "env.sh" ]; then
        if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
            log_info "env.sh を自動的に読み込みます..."
            source env.sh
        else
            log_info "環境変数が既に設定されています。env.sh の自動読み込みをスキップします。"
            log_info "env.sh を読み込む場合は手動で 'source env.sh' を実行してください。"
        fi
    fi
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
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        return 1
    }
    
    pushd terraform/network > /dev/null || {
        log_error "terraform/network に移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # terraform.tfvarsが存在しない場合は作成を促す
    if [ ! -f "terraform.tfvars" ]; then
        log_warning "terraform.tfvarsが存在しません"
        log_info "terraform.tfvars.exampleからコピーして設定してください"
        cp terraform.tfvars.example terraform.tfvars
        log_error "terraform.tfvarsを編集してから再度実行してください"
        popd > /dev/null  # terraform/networkから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        exit 1
    fi
    
    # Terraform初期化
    log_info "Terraformの初期化中..."
    terraform init
    
    # Terraform実行計画
    log_info "Terraform実行計画の作成中..."
    terraform plan -out=tfplan 2>&1 | tee /tmp/terraform_plan_network.log
    
    # 変更がない場合、スキップ（--forceオプションで強制実行可能）
    if [ "$FORCE_DEPLOY" != "true" ] && grep -q "No changes" /tmp/terraform_plan_network.log; then
        log_info "ネットワークリソースに変更はありません。スキップします。"
        log_info "強制実行する場合は --force オプションを使用してください。"
        # ネットワーク情報は既に存在するので、出力情報を表示
        echo ""
        log_info "==== ネットワーク情報 ===="
        # 全出力を一度に取得
        NETWORK_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
        if command -v jq > /dev/null 2>&1; then
            echo "VPC ID: $(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_id.value // "N/A"')"
            echo "VPC CIDR: $(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_cidr.value // "N/A"')"
            echo "Public Subnets: $(echo "$NETWORK_OUTPUTS" | jq -r '.public_subnet_ids.value // [] | join(", ")')"
            echo "Private Subnets: $(echo "$NETWORK_OUTPUTS" | jq -r '.private_subnet_ids.value // [] | join(", ")')"
        else
            echo "VPC ID: $(terraform output -raw vpc_id 2>/dev/null || echo "N/A")"
            echo "VPC CIDR: $(terraform output -raw vpc_cidr 2>/dev/null || echo "N/A")"
            echo "Public Subnets: $(terraform output -json public_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ', ' | sed 's/, $//' || echo "N/A")"
            echo "Private Subnets: $(terraform output -json private_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ', ' | sed 's/, $//' || echo "N/A")"
        fi
        popd > /dev/null  # terraform/networkから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    fi
    
    # Terraform適用
    log_info "Terraformを適用中..."
    terraform apply tfplan
    
    log_success "ネットワークリソースの構築が完了しました！"
    
    # ネットワーク情報を出力
    echo ""
    log_info "==== ネットワーク情報 ===="
    # 全出力を一度に取得
    NETWORK_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        echo "VPC ID: $(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_id.value // "N/A"')"
        echo "VPC CIDR: $(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_cidr.value // "N/A"')"
        echo "Public Subnets: $(echo "$NETWORK_OUTPUTS" | jq -r '.public_subnet_ids.value // [] | join(", ")')"
        echo "Private Subnets: $(echo "$NETWORK_OUTPUTS" | jq -r '.private_subnet_ids.value // [] | join(", ")')"
    else
        echo "VPC ID: $(terraform output -raw vpc_id 2>/dev/null || echo "N/A")"
        echo "VPC CIDR: $(terraform output -raw vpc_cidr 2>/dev/null || echo "N/A")"
        echo "Public Subnets: $(terraform output -json public_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ', ' | sed 's/, $//' || echo "N/A")"
        echo "Private Subnets: $(terraform output -json private_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ', ' | sed 's/, $//' || echo "N/A")"
    fi
    
    popd > /dev/null  # terraform/networkから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
}

# フェーズ2: ROSAクラスターのデプロイ
deploy_cluster() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ2: ROSAクラスターの構築"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        return 1
    }
    
    # ネットワークモジュールの出力を取得（1回のコマンドで全出力を取得）
    log_info "ネットワークモジュールの出力を取得中..."
    pushd terraform/network > /dev/null || {
        log_error "terraform/network に移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # 全出力を一度に取得
    NETWORK_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    
    # jqが利用可能か確認
    if command -v jq > /dev/null 2>&1; then
        VPC_ID=$(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_id.value // ""')
        VPC_CIDR=$(echo "$NETWORK_OUTPUTS" | jq -r '.vpc_cidr.value // ""')
        PUBLIC_SUBNET_IDS=$(echo "$NETWORK_OUTPUTS" | jq -r '.public_subnet_ids.value // [] | join(",")')
        PRIVATE_SUBNET_IDS=$(echo "$NETWORK_OUTPUTS" | jq -r '.private_subnet_ids.value // [] | join(",")')
        AVAILABILITY_ZONES=$(echo "$NETWORK_OUTPUTS" | jq -r '.availability_zones.value // [] | join(",")')
    else
        # jqが利用できない場合、Pythonでパース（フォールバック）
        # Pythonは通常macOS/Linuxに標準でインストールされている
        log_warning "jqが利用できません。Pythonでパースします..."
        if command -v python3 > /dev/null 2>&1; then
            # PythonでJSONをパース
            eval "$(python3 << PYTHON_SCRIPT
import sys
import json

try:
    data = json.loads('''$NETWORK_OUTPUTS''')
    vpc_id = data.get('vpc_id', {}).get('value', '')
    vpc_cidr = data.get('vpc_cidr', {}).get('value', '')
    public_subnet_ids = ','.join(data.get('public_subnet_ids', {}).get('value', []))
    private_subnet_ids = ','.join(data.get('private_subnet_ids', {}).get('value', []))
    availability_zones = ','.join(data.get('availability_zones', {}).get('value', []))
    
    print(f"VPC_ID='{vpc_id}'")
    print(f"VPC_CIDR='{vpc_cidr}'")
    print(f"PUBLIC_SUBNET_IDS='{public_subnet_ids}'")
    print(f"PRIVATE_SUBNET_IDS='{private_subnet_ids}'")
    print(f"AVAILABILITY_ZONES='{availability_zones}'")
except Exception as e:
    print("# Error parsing JSON", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)"
        else
            # Pythonもない場合、個別にterraform outputを実行（最後の手段）
            log_warning "Pythonも利用できません。個別にterraform outputを実行します..."
            VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
            VPC_CIDR=$(terraform output -raw vpc_cidr 2>/dev/null || echo "")
            PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
            PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
            AVAILABILITY_ZONES=$(terraform output -json availability_zones 2>/dev/null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' ' | xargs -n1 | tr '\n' ',' | sed 's/,$//' || echo "")
        fi
    fi
    
    if [ -z "$VPC_ID" ] || [ -z "$PUBLIC_SUBNET_IDS" ] || [ -z "$PRIVATE_SUBNET_IDS" ]; then
        log_error "ネットワークモジュールの出力を取得できませんでした"
        log_error "先にネットワークモジュールをデプロイしてください"
        popd > /dev/null  # terraform/networkから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        exit 1
    fi
    
    # terraform/networkから戻って、terraform/clusterに移動
    popd > /dev/null  # terraform/networkから戻る（SCRIPT_DIRに戻る）
    pushd terraform/cluster > /dev/null || {
        log_error "terraform/cluster に移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # terraform.tfvarsが存在しない場合は作成
    if [ ! -f "terraform.tfvars" ]; then
        log_info "terraform.tfvarsを作成中..."
        cp terraform.tfvars.example terraform.tfvars
    fi
    
    # ネットワーク情報をnetwork-outputs.auto.tfvarsに設定/更新
    # このファイルは自動生成されるため、terraform.tfvarsとは分離されています
    log_info "ネットワーク情報をnetwork-outputs.auto.tfvarsに設定中..."
    
    cat > network-outputs.auto.tfvars << EOF
# Network outputs (automatically set from network module)
# This file is automatically generated by deploy.sh
# Do not edit this file manually - it will be overwritten on each deployment
vpc_id             = "${VPC_ID}"
public_subnet_ids  = ["$(echo "$PUBLIC_SUBNET_IDS" | sed 's/,/", "/g')"]
private_subnet_ids = ["$(echo "$PRIVATE_SUBNET_IDS" | sed 's/,/", "/g')"]
availability_zones = ["$(echo "$AVAILABILITY_ZONES" | sed 's/,/", "/g')"]
EOF
    
    # Terraform初期化
    log_info "Terraformの初期化中..."
    terraform init
    
    # Terraform実行計画
    log_info "Terraform実行計画の作成中..."
    terraform plan -out=tfplan 2>&1 | tee /tmp/terraform_plan_cluster.log
    
    # 変更がない場合、スキップ（--forceオプションで強制実行可能）
    if [ "$FORCE_DEPLOY" != "true" ] && grep -q "No changes" /tmp/terraform_plan_cluster.log; then
        log_info "クラスターリソースに変更はありません。スキップします。"
        log_info "強制実行する場合は --force オプションを使用してください。"
        # クラスター情報は既に存在するので、出力情報を表示
        echo ""
        log_info "==== クラスター情報 ===="
        # 全出力を一度に取得
        CLUSTER_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
        if command -v jq > /dev/null 2>&1; then
            CLUSTER_NAME=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_name.value // "N/A"')
            CLUSTER_ID=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_id.value // "N/A"')
            CLUSTER_API_URL=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_api_url.value // "N/A"')
            CLUSTER_CONSOLE_URL=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_console_url.value // "N/A"')
        else
            CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "N/A")
            CLUSTER_ID=$(terraform output -raw cluster_id 2>/dev/null || echo "N/A")
            CLUSTER_API_URL=$(terraform output -raw cluster_api_url 2>/dev/null || echo "N/A")
            CLUSTER_CONSOLE_URL=$(terraform output -raw cluster_console_url 2>/dev/null || echo "N/A")
        fi
        echo "クラスター名: ${CLUSTER_NAME}"
        echo "クラスターID: ${CLUSTER_ID}"
        echo "API URL: ${CLUSTER_API_URL}"
        echo "Console URL: ${CLUSTER_CONSOLE_URL}"
        
        # Ansible用のクラスター情報を保存（既に存在する場合でも更新）
        log_info "Ansible用のクラスター情報を保存中..."
        mkdir -p ../../ansible
        if command -v jq > /dev/null 2>&1; then
            echo "$CLUSTER_OUTPUTS" | jq -r '.ansible_inventory_json.value // ""' > ../../ansible/cluster_info.json
        else
            terraform output -raw ansible_inventory_json > ../../ansible/cluster_info.json
        fi
        
        popd > /dev/null  # terraform/clusterから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    fi
    
    # Terraform適用
    log_info "Terraformを適用中（時間がかかります、約30-40分）..."
    log_info "注意: wait_for_create_complete = true のため、Terraformがクラスター構築の完了を待機します"
    terraform apply tfplan
    
    log_success "Terraformによるクラスター構築が完了しました！"
    echo ""
    
    # 出力情報の表示（wait_for_create_complete = trueなので、情報は確実に取得できる）
    echo ""
    log_info "==== クラスター情報 ===="
    # 全出力を一度に取得
    CLUSTER_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        CLUSTER_NAME=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_name.value // "N/A"')
        CLUSTER_ID=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_id.value // "N/A"')
        CLUSTER_API_URL=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_api_url.value // "N/A"')
        CLUSTER_CONSOLE_URL=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_console_url.value // "N/A"')
    else
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "N/A")
        CLUSTER_ID=$(terraform output -raw cluster_id 2>/dev/null || echo "N/A")
        CLUSTER_API_URL=$(terraform output -raw cluster_api_url 2>/dev/null || echo "N/A")
        CLUSTER_CONSOLE_URL=$(terraform output -raw cluster_console_url 2>/dev/null || echo "N/A")
    fi
    echo "クラスター名: ${CLUSTER_NAME}"
    echo "クラスターID: ${CLUSTER_ID}"
    echo "API URL: ${CLUSTER_API_URL}"
    echo "Console URL: ${CLUSTER_CONSOLE_URL}"
    
    echo ""
    log_info "クラスターが準備できたら、以下でログインできます："
    echo "  oc login <API_URL> -u <USER> -p <PASSWORD>"
    echo ""
    log_warning "管理者パスワードを確認するには以下を実行してください："
    echo "  cd terraform/cluster && terraform output cluster_admin_password"
    
    # Ansible用のクラスター情報を保存
    log_info "Ansible用のクラスター情報を保存中..."
    mkdir -p ../../ansible
    if command -v jq > /dev/null 2>&1; then
        echo "$CLUSTER_OUTPUTS" | jq -r '.ansible_inventory_json.value // ""' > ../../ansible/cluster_info.json
    else
        terraform output -raw ansible_inventory_json > ../../ansible/cluster_info.json
    fi
    
    # DevSpaces用のAWS Role ARNはAnsibleで設定されます
    log_info "DevSpaces用のAWS Role ARNはAnsible実行時に設定されます"
    
    popd > /dev/null  # terraform/clusterから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
}

# Ansibleによる追加設定
run_ansible() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ステップ7: Ansibleによる追加設定"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Ansibleがインストールされているか確認
    if ! command -v ansible-playbook &> /dev/null; then
        log_warning "Ansibleがインストールされていません。Ansible実行をスキップします"
        return 0
    fi
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        return 1
    }
    
    pushd ansible > /dev/null || {
        log_error "ansible ディレクトリに移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # cluster_info.jsonが存在するか確認
    if [ ! -f "cluster_info.json" ]; then
        log_warning "cluster_info.jsonが見つかりません。Ansible実行をスキップします"
        popd > /dev/null  # ansibleから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    fi
    
    # Ansible Galaxy requirementsのインストール
    if [ -f "requirements.yml" ]; then
        log_info "Ansible Galaxy requirementsをインストール中..."
        ansible-galaxy collection install -r requirements.yml
    fi
    
    # GitOps環境の設定（デフォルト: mta）
    GITOPS_ENV="${GITOPS_ENV:-mta}"
    log_info "GitOps環境: ${GITOPS_ENV}"
    
    # Ansible playbook実行
    log_info "Ansible playbookを実行中..."
    if ansible-playbook playbooks/site.yml -e "gitops_env=${GITOPS_ENV}"; then
        log_success "Ansible playbookの実行が完了しました"
        popd > /dev/null  # ansibleから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    else
        log_error "Ansible playbookの実行に失敗しました"
        popd > /dev/null  # ansibleから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 1
    fi
}

# クラスターへのログイン確認
verify_cluster_access() {
    log_info "クラスターへのアクセスを確認中..."
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        return 1
    }
    
    pushd terraform/cluster > /dev/null || {
        log_error "terraform/cluster に移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # 全出力を一度に取得
    CLUSTER_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        CLUSTER_API=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_api_url.value // ""')
        ADMIN_USER=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_admin_username.value // ""')
        ADMIN_PASS=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_admin_password.value // ""')
    else
        CLUSTER_API=$(terraform output -raw cluster_api_url 2>/dev/null || echo "")
        ADMIN_USER=$(terraform output -raw cluster_admin_username 2>/dev/null || echo "")
        ADMIN_PASS=$(terraform output -raw cluster_admin_password 2>/dev/null || echo "")
    fi
    
    popd > /dev/null  # terraform/clusterから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
    
    if [ -z "$CLUSTER_API" ] || [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
        log_warning "クラスター情報がまだ利用できません"
        return 1
    fi
    
    # 既にログイン済みか確認
    if oc whoami > /dev/null 2>&1; then
        CURRENT_CLUSTER=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
        # URLの正規化（末尾のスラッシュやポート番号の違いを考慮）
        CURRENT_CLUSTER_NORMALIZED=$(echo "$CURRENT_CLUSTER" | sed 's|/$||' | sed 's|:443$||')
        EXPECTED_CLUSTER_NORMALIZED=$(echo "$CLUSTER_API" | sed 's|/$||' | sed 's|:443$||')
        
        if [ -n "$CURRENT_CLUSTER_NORMALIZED" ] && [ "$CURRENT_CLUSTER_NORMALIZED" = "$EXPECTED_CLUSTER_NORMALIZED" ]; then
            log_info "既にクラスターにログイン済みです。スキップします。"
            echo ""
            log_info "==== ノード情報 ===="
            oc get nodes 2>/dev/null || true
            echo ""
            log_info "==== クラスターバージョン ===="
            oc get clusterversion 2>/dev/null || true
            return 0
        fi
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
    
    # ステップ1.5: env.shの自動読み込み（必要な場合）
    load_env_if_needed
    
    # ステップ2: 環境変数の確認
    check_environment
    
    # ステップ3: ROSAの準備
    rosa_login
    
    # ステップ4: フェーズ1 - ネットワークリソースの構築
    deploy_network
    
    # ステップ5: フェーズ2 - ROSAクラスターの構築
    deploy_cluster
    
    # ステップ6: クラスター構築の完了確認
    # Terraformが wait_for_create_complete = true で完了を待機したため、
    # 追加の待機処理は不要です
    log_info "クラスター構築はTerraformで完了しました"
    
    # ステップ7: クラスターアクセス確認
    verify_cluster_access
    
    # ステップ8: Ansibleによる追加設定（環境変数で有効化された場合のみ）
    if [ "${RUN_ANSIBLE:-}" = "true" ]; then
        run_ansible
    else
        log_info "Ansible実行はスキップされます（RUN_ANSIBLE=true を設定すると実行されます）"
    fi
    
    # 完了メッセージ
    echo ""
    log_success "======================================"
    log_success "  環境構築が完了しました！"
    log_success "======================================"
    echo ""
    
    # クラスター情報を取得して表示
    pushd "$SCRIPT_DIR" > /dev/null || return 1
    pushd terraform/cluster > /dev/null || {
        popd > /dev/null
        return 1
    }
    # 全出力を一度に取得
    CLUSTER_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        CLUSTER_API=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_api_url.value // ""')
        CONSOLE_URL=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_console_url.value // ""')
        ADMIN_USER=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_admin_username.value // ""')
        ADMIN_PASS=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_admin_password.value // ""')
    else
        CLUSTER_API=$(terraform output -raw cluster_api_url 2>/dev/null || echo "")
        CONSOLE_URL=$(terraform output -raw cluster_console_url 2>/dev/null || echo "")
        ADMIN_USER=$(terraform output -raw cluster_admin_username 2>/dev/null || echo "")
        ADMIN_PASS=$(terraform output -raw cluster_admin_password 2>/dev/null || echo "")
    fi
    popd > /dev/null  # terraform/clusterから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
    
    log_info "次のステップ："
    echo ""
    echo "  1. クラスターにログイン"
    if [ -n "$CLUSTER_API" ] && [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
        echo "     oc login ${CLUSTER_API} -u ${ADMIN_USER} -p ${ADMIN_PASS}"
    else
        echo "     oc login <API_URL> -u cluster-admin -p <PASSWORD>"
    fi
    echo ""
    echo "  2. OpenShift Consoleにアクセス"
    if [ -n "$CONSOLE_URL" ]; then
        echo "     ${CONSOLE_URL}"
    else
        echo "     上記のConsole URLをブラウザで開いてください"
    fi
    echo ""
    
    # 補足: HTPasswd IDPユーザーの情報
    # 環境変数（TF_VAR_*）から取得
    ADMIN_COUNT="${TF_VAR_admin_count:-1}"
    WORKSHOP_USER_COUNT="${TF_VAR_workshop_user_count:-20}"
    ADMIN_PASSWORD="${TF_VAR_admin_password:-}"
    WORKSHOP_PASSWORD="${TF_VAR_workshop_user_password:-}"
    DEVELOPER_PASSWORD="${TF_VAR_developer_password:-}"
    
    # HTPasswd IDPユーザーが存在する場合、補足情報を表示
    if [ -n "$ADMIN_PASSWORD" ] || [ -n "$WORKSHOP_PASSWORD" ] || [ -n "$DEVELOPER_PASSWORD" ]; then
        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "補足: HTPasswd IDPユーザー"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        if [ -n "$ADMIN_PASSWORD" ] && [ -n "$CLUSTER_API" ]; then
            if [ "$ADMIN_COUNT" = "1" ]; then
                echo "  • 管理者ユーザー: admin"
                echo "    ログイン例: oc login ${CLUSTER_API} -u admin -p ${ADMIN_PASSWORD}"
            else
                echo "  • 管理者ユーザー: admin, admin2, ..., admin${ADMIN_COUNT}"
                echo "    ログイン例: oc login ${CLUSTER_API} -u admin -p ${ADMIN_PASSWORD}"
            fi
            echo ""
        fi
        
        if [ -n "$WORKSHOP_PASSWORD" ] && [ -n "$CLUSTER_API" ]; then
            echo "  • ワークショップユーザー: user1, user2, ..., user${WORKSHOP_USER_COUNT}"
            echo "    ログイン例: oc login ${CLUSTER_API} -u user1 -p ${WORKSHOP_PASSWORD}"
            echo ""
        fi
        
        if [ -n "$DEVELOPER_PASSWORD" ] && [ -n "$CLUSTER_API" ]; then
            echo "  • 開発者ユーザー: developer"
            echo "    ログイン例: oc login ${CLUSTER_API} -u developer -p ${DEVELOPER_PASSWORD}"
            echo ""
        fi
    fi
}

# スクリプト実行
main "$@"

