#!/bin/bash

###############################################################################
# MTA for Developer Lightspeed ワークショップ環境削除スクリプト
# 
# このスクリプトは以下を実行します：
# 1. Terraformを使用してROSA HCPクラスターを削除
# 2. rosaコマンドでクラスター削除の完了を確認
#
# オプション:
#   --log-file <file>           ログを指定ファイルに出力
#   -l, --log                   ログをデフォルトファイル名で出力（destroy-YYYYMMDD-HHMMSS.log）
#   --verify-only               削除は行わず、Terraform状態・ROSA・VPCの残存確認のみ実行
#   --skip-verify               削除後の状態検証をスキップ（自動化用）
#   --force-cluster-mode <mode> メタデータを無視してクラスター削除方式を上書き: 'terraform' または 'rosa-cli'
#   -h, --help                  ヘルプを表示
#
# 環境変数:
#   DESTROY_LOG_FILE        ログファイルパス（--log-fileオプションで上書き可能）
#   DESTROY_NO_STATE_PRUNE  1 のとき、検証フェーズで terraform state rm による整理を行わない
###############################################################################

# スクリプトのディレクトリを取得（プロジェクトルートに移動）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ログファイル設定（環境変数から読み込み）
LOG_FILE="${DESTROY_LOG_FILE:-}"
VERIFY_ONLY=false
SKIP_VERIFY=false
FORCE_CLUSTER_MODE=""  # terraform | rosa-cli（空=メタデータ自動検出）

# オプション解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -l|--log)
            if [ -z "$LOG_FILE" ]; then
                LOG_FILE="destroy-$(date +%Y%m%d-%H%M%S).log"
            fi
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --force-cluster-mode)
            FORCE_CLUSTER_MODE="$2"
            if [[ "$FORCE_CLUSTER_MODE" != "terraform" && "$FORCE_CLUSTER_MODE" != "rosa-cli" ]]; then
                echo "Error: --force-cluster-mode must be 'terraform' or 'rosa-cli'" >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --log-file <file>           Log output to specified file
  -l, --log                   Log output to default file (destroy-YYYYMMDD-HHMMSS.log)
  --verify-only               Only check Terraform state / ROSA / AWS leftovers (no destroy)
  --skip-verify               Skip post-destroy verification
  --force-cluster-mode <mode> Override cluster delete mode: 'terraform' or 'rosa-cli'
                              (use when metadata file is missing or after manual operations)
  -h, --help                  Show this help message

Environment Variables:
  DESTROY_LOG_FILE        Log file path (overridden by --log-file option)
  DESTROY_NO_STATE_PRUNE  Set to 1 to skip automatic terraform state rm when cloud is clean

Examples:
  $0 --log
  $0 --log-file my-destroy.log
  DESTROY_LOG_FILE=destroy.log $0
  $0 --verify-only
  $0 --force-cluster-mode rosa-cli
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

# set -e をコメントアウト（エラーを無視して続行するため）
# set -e  # エラーが発生したら即座に終了

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
    echo -e "${RED}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║  MTA for Developer Lightspeed Workshop Environment            ║
║  Red Hat OpenShift for AWS (ROSA) Cluster Destruction         ║
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
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "以下のツールがインストールされていません："
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        log_info "インストール方法："
        echo "  brew install terraform awscli rosa-cli"
        exit 1
    fi
    
    log_success "すべての必要なツールが確認されました"
}

# プロファイル読み込み
load_profile() {
    if [ -z "${PROFILE:-}" ]; then
        log_warning "PROFILE が未設定です。デフォルト 'mta-full' を使用します。"
        log_info "明示的に指定する場合: export PROFILE=\"<profile-name>\""
        log_info "利用可能: $(ls "${SCRIPT_DIR}/profiles/"*.env 2>/dev/null | xargs -I{} basename {} .env | tr '\n' ' ')"
        PROFILE="mta-full"
    fi

    local profile_file="${SCRIPT_DIR}/profiles/${PROFILE}.env"
    if [ -f "$profile_file" ]; then
        source "$profile_file"
        log_success "プロファイル '${PROFILE}' を読み込みました"
    else
        log_error "プロファイル '${PROFILE}' が見つかりません: ${profile_file}"
        log_info "利用可能: $(ls "${SCRIPT_DIR}/profiles/"*.env 2>/dev/null | xargs -I{} basename {} .env | tr '\n' ' ')"
        exit 1
    fi
}

# env.shの自動読み込み（認証情報）
load_env_if_needed() {
    if [ -f "env.sh" ]; then
        if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
            log_info "env.sh を自動的に読み込みます..."
            source env.sh
        else
            log_info "環境変数が既に設定されています。env.sh の自動読み込みをスキップします。"
        fi
    fi
}

# ROSA CLIのログイン確認
ensure_rosa_auth() {
    log_info "ROSA認証状態の確認中..."
    
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

    log_info "Terraform 用の RHCS 認証は環境変数から行われます。"
    log_info "推奨: サービスアカウントの RHCS_CLIENT_ID / RHCS_CLIENT_SECRET を env.sh に設定してください。"
}

# クラスター起源メタデータからプロビジョナーを読み取る
# 出力: "rosa-cli" | "terraform" | ""（ファイル未存在時）
# 終了コード: 0=ファイルあり, 1=ファイルなし
read_cluster_origin_provisioner() {
    local metadata_file="${SCRIPT_DIR}/.mta-demo/cluster-origin.json"

    if [ ! -f "$metadata_file" ]; then
        echo ""
        return 1
    fi

    local provisioner=""
    if command -v jq > /dev/null 2>&1; then
        provisioner=$(jq -r '.provisioner // ""' "$metadata_file" 2>/dev/null || echo "")
    else
        provisioner=$(python3 -c \
            "import json,sys; d=json.load(open('${metadata_file}')); print(d.get('provisioner',''))" \
            2>/dev/null || echo "")
    fi
    echo "$provisioner"
    return 0
}

# クラスター起源メタデータからクラスター名を読み取る（フォールバック: TF_VAR_cluster_name）
read_cluster_origin_name() {
    local metadata_file="${SCRIPT_DIR}/.mta-demo/cluster-origin.json"
    local name=""

    if [ -f "$metadata_file" ]; then
        if command -v jq > /dev/null 2>&1; then
            name=$(jq -r '.cluster_name // ""' "$metadata_file" 2>/dev/null || echo "")
        else
            name=$(python3 -c \
                "import json,sys; d=json.load(open('${metadata_file}')); print(d.get('cluster_name',''))" \
                2>/dev/null || echo "")
        fi
    fi

    if [ -z "$name" ]; then
        name="${TF_VAR_cluster_name:-mta-lightspeed}"
    fi
    echo "$name"
}

# クラスター名の取得
get_cluster_name() {
    local cluster_name=""
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        echo "mta-lightspeed"
        return 1
    }
    
    # terraform/clusterディレクトリが存在するか確認
    if [ ! -d "terraform/cluster" ]; then
        log_warning "terraform/cluster ディレクトリが見つかりません。環境変数からクラスター名を取得します。"
        cluster_name="${TF_VAR_cluster_name:-mta-lightspeed}"
        popd > /dev/null
        echo "$cluster_name"
        return 0
    fi
    
    pushd terraform/cluster > /dev/null || {
        log_error "terraform/cluster に移動できませんでした"
        popd > /dev/null
        echo "mta-lightspeed"
        return 1
    }
    
    # 方法1: Terraform outputから取得（全出力を一度に取得）
    CLUSTER_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        cluster_name=$(echo "$CLUSTER_OUTPUTS" | jq -r '.cluster_name.value // ""')
    else
        if terraform output -raw cluster_name > /dev/null 2>&1; then
            cluster_name=$(terraform output -raw cluster_name 2>/dev/null)
        fi
    fi
    
    # 方法2: 環境変数から取得
    if [ -z "$cluster_name" ]; then
        cluster_name="${TF_VAR_cluster_name:-mta-lightspeed}"
    fi
    
    # 方法3: terraform.tfvarsから取得
    if [ -z "$cluster_name" ] && [ -f "terraform.tfvars" ]; then
        cluster_name=$(grep -E "^cluster_name\s*=" terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' | sed "s/.*=\s*\([^ ]*\).*/\1/" | head -1)
    fi
    
    # デフォルト値
    if [ -z "$cluster_name" ]; then
        cluster_name="mta-lightspeed"
    fi
    
    # スタックを2つ戻す（terraform/cluster → SCRIPT_DIR → 元のディレクトリ）
    popd > /dev/null
    popd > /dev/null
    echo "$cluster_name"
}

# MachinePoolとIdentity Providerを手動削除（Terraformで管理されていないリソース用）
# 注意: Terraformで管理されているリソース（rhcs_hcp_machine_pool、rhcs_identity_provider）は
# terraform destroyで削除されるため、この関数は通常は使用されません。
cleanup_cluster_resources() {
    local cluster_name="$1"
    
    if [ -z "$cluster_name" ]; then
        log_warning "クラスター名が指定されていません。スキップします"
        return 0
    fi
    
    log_info "クラスター名: ${cluster_name}"
    
    # MachinePoolを削除（403エラーが発生する可能性があるため、ROSA CLIで削除を試みる）
    log_info "追加のMachinePoolを削除中..."
    MACHINE_POOLS=$(rosa list machinepools -c "${cluster_name}" --output json 2>/dev/null | jq -r '.[] | select(.id != "workers") | .id' 2>/dev/null || echo "")
    
    if [ -n "$MACHINE_POOLS" ]; then
        for pool in $MACHINE_POOLS; do
            log_info "MachinePool '${pool}' を削除中..."
            if rosa delete machinepool -c "${cluster_name}" --machinepool "${pool}" --yes 2>&1; then
                log_success "MachinePool '${pool}' を削除しました"
            else
                log_warning "MachinePool '${pool}' の削除に失敗しました（既に削除済みの可能性があります）"
            fi
        done
    else
        log_info "削除対象のMachinePoolはありません"
    fi
    
    # Identity Providerを削除（403エラーが発生する可能性があるため、ROSA CLIで削除を試みる）
    log_info "Identity Providerを削除中..."
    IDPS=$(rosa list idp -c "${cluster_name}" --output json 2>/dev/null | jq -r '.[] | .id' 2>/dev/null || echo "")
    
    if [ -n "$IDPS" ]; then
        for idp in $IDPS; do
            log_info "Identity Provider '${idp}' を削除中..."
            if rosa delete idp -c "${cluster_name}" --idp "${idp}" --yes 2>&1; then
                log_success "Identity Provider '${idp}' を削除しました"
            else
                log_warning "Identity Provider '${idp}' の削除に失敗しました（既に削除済みの可能性があります）"
            fi
        done
    else
        log_info "削除対象のIdentity Providerはありません"
    fi
}

# フェーズ1: ROSAクラスターの削除
destroy_cluster() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ1: ROSAクラスターの削除"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # プロジェクトルートに移動
    pushd "$SCRIPT_DIR" > /dev/null || {
        log_error "プロジェクトルートに移動できませんでした"
        return 1
    }
    
    # terraform/clusterディレクトリが存在するか確認
    if [ ! -d "terraform/cluster" ]; then
        log_warning "terraform/cluster ディレクトリが見つかりません。"
        log_info "既に削除済みの可能性があります。"
        popd > /dev/null
        return 0
    fi
    
    pushd terraform/cluster > /dev/null || {
        log_error "terraform/cluster に移動できませんでした"
        popd > /dev/null
        return 1
    }
    
    # Terraform状態ファイルの確認
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        log_warning "Terraform状態ファイルが見つかりません"
        log_info "既に削除済みの可能性があります"
        popd > /dev/null  # terraform/clusterから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    fi
    
    # クラスター名を取得
    CLUSTER_NAME=$(get_cluster_name)
    log_info "クラスター名: ${CLUSTER_NAME}"
    
    # MachinePoolとIdentity ProviderはTerraformで管理されているため、
    # terraform destroyで削除される（事前削除は不要）
    
    # Terraform destroy実行（エラーは無視して後続処理を継続）
    log_info "Terraform destroyを実行中..."
    # set +e でエラーを無視
    set +e
    terraform destroy -auto-approve 2>&1 | tee /tmp/terraform_destroy_cluster.log
    DESTROY_EXIT_CODE=$?
    set -e
    
    # 403エラーを検出
    if grep -q "403\|Forbidden" /tmp/terraform_destroy_cluster.log 2>/dev/null; then
        log_error "Terraform destroyで権限エラー（403 Forbidden）が発生しました"
        log_error "クラスター '${CLUSTER_NAME}' の削除権限がありません"
        log_info "対処方法:"
        echo "  1. クラスター作成時に使用したアカウント（RHCS_CLIENT_ID/CLIENT_SECRET）で認証しているか確認"
        echo "  2. Hybrid Cloud Consoleでクラスターの所有者権限があるか確認"
        echo "  3. クラスター作成者に削除を依頼するか、適切な権限を付与してもらう"
    fi
    
    # クラスターリソースの削除が試みられたか確認
    if grep -q "rhcs_cluster_rosa_hcp.rosa_hcp_cluster.*Destroying\|rhcs_cluster_rosa_hcp.rosa_hcp_cluster.*destroyed" /tmp/terraform_destroy_cluster.log 2>/dev/null; then
        log_success "Terraform destroyでクラスター削除リクエストが送信されました！"
        log_info "注意: Terraformは削除リクエストを送信して即座に完了します"
    elif [ $DESTROY_EXIT_CODE -eq 0 ]; then
        log_success "Terraform destroyが完了しました"
    else
        log_warning "Terraform destroyでエラーが発生しました（Exit Code: ${DESTROY_EXIT_CODE}）"
        log_info "クラスターの削除状態を確認します..."
        
        # クラスターが削除中か確認
        sleep 5
        if rosa describe cluster -c "${CLUSTER_NAME}" > /dev/null 2>&1; then
            CLUSTER_STATE=$(rosa describe cluster -c "${CLUSTER_NAME}" --output json 2>/dev/null | jq -r '.state' 2>/dev/null || echo "unknown")
            if [ "$CLUSTER_STATE" != "ready" ]; then
                log_info "クラスターは '${CLUSTER_STATE}' 状態です。削除が進行中の可能性があります"
            else
                log_warning "クラスターはまだ 'ready' 状態です。手動で削除を試みます..."
                # rosa delete cluster を試みる
                if rosa delete cluster -c "${CLUSTER_NAME}" --yes 2>&1; then
                    log_success "ROSA CLIでクラスター削除リクエストを送信しました"
                else
                    log_error "ROSA CLIでのクラスター削除にも失敗しました"
                fi
            fi
        else
            log_info "クラスターは既に存在しません"
        fi
    fi
    
    log_info "次のステップで rosa コマンドでクラスター削除の完了を確認します"
    echo ""
    
    # スタックを2つ戻す（terraform/cluster → SCRIPT_DIR → 元のディレクトリ）
    popd > /dev/null
    popd > /dev/null
}

# フェーズ2: ネットワークリソースの削除
destroy_network() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ2: ネットワークリソースの削除"
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
    
    # Terraform状態ファイルの確認
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        log_warning "Terraform状態ファイルが見つかりません"
        log_info "既に削除済みの可能性があります"
        popd > /dev/null  # terraform/networkから戻る
        popd > /dev/null  # SCRIPT_DIRから戻る
        return 0
    fi
    
    # Terraform destroy実行（最大3回まで再試行）
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        log_info "Terraform destroyを実行中... (試行: $((RETRY_COUNT + 1))/${MAX_RETRIES})"
        
        if terraform destroy -auto-approve 2>&1 | tee /tmp/terraform_destroy.log; then
            log_success "ネットワークリソースの削除が完了しました！"
            echo ""
            popd > /dev/null  # terraform/networkから戻る
            popd > /dev/null  # SCRIPT_DIRから戻る
            return 0
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            
            # エラーログを確認
            if grep -q "DependencyViolation\|has dependencies" /tmp/terraform_destroy.log; then
                log_warning "依存関係エラーが発生しました（試行: ${RETRY_COUNT}/${MAX_RETRIES}）"
                
                if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                    log_info "ENIのクリーンアップを待機してから再試行します..."
                    popd > /dev/null  # terraform/networkから戻る
                    wait_for_eni_cleanup
                    pushd terraform/network > /dev/null || {
                        log_error "terraform/network に再移動できませんでした"
                        popd > /dev/null
                        return 1
                    }
                    sleep 10  # 追加の待機時間
                else
                    log_error "最大再試行回数に達しました"
                    log_info "手動でENIを確認・削除してから、再度 terraform destroy を実行してください："
                    echo ""
                    echo "  # VPC IDを取得"
                    echo "  cd terraform/network"
                    echo "  VPC_ID=\$(terraform output -raw vpc_id)"
                    echo ""
                    echo "  # 残っているENIを確認"
                    echo "  aws ec2 describe-network-interfaces --filters \"Name=vpc-id,Values=\${VPC_ID}\" --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' --output table"
                    echo ""
                    echo "  # 必要に応じてENIを削除（注意: 他のリソースで使用中のENIは削除できません）"
                    echo "  # aws ec2 delete-network-interface --network-interface-id <eni-id>"
                    echo ""
                    popd > /dev/null  # terraform/networkから戻る
                    popd > /dev/null  # SCRIPT_DIRから戻る
                    return 1
                fi
            else
                log_error "予期しないエラーが発生しました"
                popd > /dev/null  # terraform/networkから戻る
                popd > /dev/null  # SCRIPT_DIRから戻る
                return 1
            fi
        fi
    done
    
    popd > /dev/null  # terraform/networkから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
    return 1
}

# ROSAコマンドでクラスター削除のログを監視して完了を待つ
wait_for_cluster_deletion() {
    CLUSTER_NAME=$(get_cluster_name)
    
    if [ -z "$CLUSTER_NAME" ]; then
        log_warning "クラスター名を取得できませんでした。スキップします"
        return 0
    fi

    # クラスターが既に存在しない場合は、ログ監視をスキップ
    if ! rosa describe cluster -c "${CLUSTER_NAME}" > /dev/null 2>&1; then
        log_warning "クラスター '${CLUSTER_NAME}' は既に存在しません。削除ログの監視をスキップします"
        return 0
    fi

    log_info "クラスター名: ${CLUSTER_NAME}"
    log_info "rosa logs uninstall で削除ログを監視します..."
    echo ""
    log_warning "注意: クラスター削除には約10-20分かかります"
    echo ""
    
    # rosa logs uninstall --watch で削除ログを監視
    # このコマンドはクラスター削除が完了するまで待機します
    if rosa logs uninstall -c "${CLUSTER_NAME}" --watch; then
        log_success "クラスター削除が完了しました！"
        
        # 念のため、クラスターが存在しないことを確認
        sleep 5
        if ! rosa describe cluster -c "${CLUSTER_NAME}" > /dev/null 2>&1; then
            log_success "クラスター '${CLUSTER_NAME}' が完全に削除されたことを確認しました"
            return 0
        else
            log_warning "rosa logs uninstall は完了しましたが、クラスターがまだ存在する可能性があります"
            log_info "手動で確認してください："
            echo "  rosa describe cluster -c ${CLUSTER_NAME}"
            return 1
        fi
    else
        log_error "クラスター削除の監視中にエラーが発生しました"
        log_info "クラスターの削除状態を手動で確認してください："
        echo "  rosa describe cluster -c ${CLUSTER_NAME}"
        echo "  rosa list clusters"
        return 1
    fi
}

# フェーズ1（ROSA CLI）: ROSA CLI でクラスターを削除する
# - terraform/cluster は apply していないため terraform destroy をスキップ
# - Terraform 用 RHCS SA は不要。env -u で RHCS 変数を除いて rosa を起動する
#   （rosa がバージョン依存で RHCS_* を読む可能性があるため防御的に unset する）
# $1: cluster_name
destroy_cluster_rosa_cli() {
    local cluster_name="$1"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "フェーズ1: ROSAクラスターの削除（ROSA CLI 経由）"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "クラスター名: ${cluster_name}"
    log_info "注意: terraform/cluster は CLI で構築したため Terraform destroy をスキップします"
    log_info "RHCS_CLIENT_ID / RHCS_CLIENT_SECRET / RHCS_TOKEN を unset して rosa を呼び出します"

    if ! env -u RHCS_CLIENT_ID -u RHCS_CLIENT_SECRET -u RHCS_TOKEN \
            rosa describe cluster -c "${cluster_name}" > /dev/null 2>&1; then
        log_info "クラスター '${cluster_name}' は既に存在しません。スキップします"
        return 0
    fi

    set +e
    env -u RHCS_CLIENT_ID -u RHCS_CLIENT_SECRET -u RHCS_TOKEN \
        rosa delete cluster -c "${cluster_name}" --yes 2>&1
    local delete_exit=$?
    set -e

    if [ $delete_exit -eq 0 ]; then
        log_success "ROSA CLI クラスター削除リクエストを送信しました"
        log_info "次のステップで rosa logs uninstall --watch により完了を確認します"
    else
        log_error "ROSA CLI でのクラスター削除リクエスト送信に失敗しました（exit: ${delete_exit}）"
        log_info "手動で確認してください: rosa describe cluster -c ${cluster_name}"
        return 1
    fi
}

# ROSA クラスターに紐づく IAM ロール（Account / Operator）と OIDC provider を削除する
# Terraform モード・ROSA CLI モード問わずクラスター削除完了後に呼ぶ。
# 冪等: 既に削除済みの場合もエラーにしない。
# $1: cluster_name（Account Role prefix = {name}-account, Operator Role prefix = {name}-operator-roles）
cleanup_iam_resources() {
    local cluster_name="$1"
    local account_role_prefix="${cluster_name}-account"
    local operator_role_prefix="${cluster_name}-operator-roles"
    local region="${AWS_DEFAULT_REGION:-ap-northeast-1}"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "IAM リソースのクリーンアップ（Account / Operator ロール + OIDC）"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "クラスター名: ${cluster_name}"
    log_info "Account Role prefix: ${account_role_prefix}"
    log_info "Operator Role prefix: ${operator_role_prefix}"

    # Operator ロールの削除
    log_info "Operator ロールを削除中（prefix: ${operator_role_prefix}）..."
    set +e
    rosa delete operator-roles --prefix "${operator_role_prefix}" --mode auto --yes 2>&1
    local op_exit=$?
    set -e
    if [ $op_exit -eq 0 ]; then
        log_success "Operator ロールを削除しました"
    else
        log_warning "Operator ロールの削除に失敗またはスキップ（既に削除済み、または存在しない可能性）"
    fi

    # OIDC provider の削除（クラスター固有の OIDC config ID を特定して削除）
    # rosa delete oidc-config は ID が必要だが、クラスター削除後は特定が困難なため
    # ここでは OIDC provider（AWS 側）のみ削除を試みる
    log_info "OIDC provider の削除を試行中..."
    local oidc_providers
    oidc_providers=$(aws iam list-open-id-connect-providers \
        --query 'OpenIDConnectProviderList[*].Arn' \
        --output text --region "$region" 2>/dev/null || echo "")
    if [ -n "$oidc_providers" ]; then
        for arn in $oidc_providers; do
            local tags
            tags=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" \
                --query 'Tags[?Key==`rosa_cluster_id` || Key==`cluster_name`].Value' \
                --output text 2>/dev/null || echo "")
            if echo "$tags" | grep -qi "${cluster_name}" 2>/dev/null; then
                log_info "  削除: ${arn}"
                aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$arn" 2>&1 || true
            fi
        done
    fi

    # Account ロールの削除
    log_info "Account ロールを削除中（prefix: ${account_role_prefix}）..."
    set +e
    rosa delete account-roles --prefix "${account_role_prefix}" --mode auto --yes 2>&1
    local acct_exit=$?
    set -e
    if [ $acct_exit -eq 0 ]; then
        log_success "Account ロールを削除しました"
    else
        log_warning "Account ロールの削除に失敗またはスキップ（既に削除済み、または存在しない可能性）"
    fi

    log_success "IAM リソースのクリーンアップが完了しました"
}

# 後方互換エイリアス
cleanup_rosa_cli_iam_resources() {
    cleanup_iam_resources "$@"
}

# VPC IDをterraform/network出力から取得するヘルパー
get_vpc_id_from_network() {
    pushd "$SCRIPT_DIR" > /dev/null || return 1
    pushd terraform/network > /dev/null || {
        popd > /dev/null
        return 1
    }
    local outputs
    outputs=$(terraform output -json 2>/dev/null || echo "{}")
    if command -v jq > /dev/null 2>&1; then
        echo "$outputs" | jq -r '.vpc_id.value // ""'
    else
        terraform output -raw vpc_id 2>/dev/null || echo ""
    fi
    popd > /dev/null
    popd > /dev/null
}

# VPC内のENI（Elastic Network Interface）が削除されるまで待つ
wait_for_eni_cleanup() {
    log_info "VPC内のENI（Elastic Network Interface）のクリーンアップを待機中..."
    
    VPC_ID=$(get_vpc_id_from_network)
    
    if [ -z "$VPC_ID" ]; then
        log_warning "VPC IDを取得できませんでした。ENIクリーンアップの待機をスキップします"
        return 0
    fi
    
    log_info "VPC ID: ${VPC_ID}"
    log_info "ROSAクラスター関連のENIが削除されるまで待機します（最大5分）..."
    echo ""
    
    MAX_WAIT=300  # 5分
    ELAPSED=0
    INTERVAL=10   # 10秒ごとにチェック
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        ATTACHED_ENI_COUNT=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=in-use" \
            --query 'length(NetworkInterfaces)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$ATTACHED_ENI_COUNT" = "0" ] || [ -z "$ATTACHED_ENI_COUNT" ]; then
            log_success "VPC内のin-use ENIがクリーンアップされました"
            return 0
        fi
        
        log_info "ENI削除待機中... (残り: ${ATTACHED_ENI_COUNT}個のENI, 経過: ${ELAPSED}秒)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    log_warning "ENIのクリーンアップが完了しませんでした（タイムアウト: ${MAX_WAIT}秒）"
    log_info "残っているENIを確認してください："
    echo "  aws ec2 describe-network-interfaces --filters \"Name=vpc-id,Values=${VPC_ID}\" --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' --output table"
    return 0
}

# VPC内のROSAが残した孤立リソース（Security Group, ENI, VPC Endpoint）を削除する
# terraform destroy の前に呼ぶことで DependencyViolation によるハングを防止する
cleanup_vpc_orphaned_resources() {
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "VPC内の孤立リソースのクリーンアップ"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    VPC_ID=$(get_vpc_id_from_network)

    if [ -z "$VPC_ID" ]; then
        log_info "VPC IDを取得できませんでした。スキップします"
        return 0
    fi

    log_info "VPC ID: ${VPC_ID}"
    local region="${AWS_DEFAULT_REGION:-ap-northeast-1}"

    # 1. VPC Endpoints の削除
    local endpoint_ids
    endpoint_ids=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[*].VpcEndpointId' \
        --output text --region "$region" 2>/dev/null || echo "")

    if [ -n "$endpoint_ids" ] && [ "$endpoint_ids" != "None" ]; then
        log_info "VPC Endpoints を削除中..."
        for ep_id in $endpoint_ids; do
            log_info "  削除: ${ep_id}"
            aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep_id" --region "$region" 2>&1 || true
        done
        sleep 5
    fi

    # 2. available 状態の ENI を削除（デタッチ済みだが残っているもの）
    local avail_enis
    avail_enis=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' \
        --output text --region "$region" 2>/dev/null || echo "")

    if [ -n "$avail_enis" ] && [ "$avail_enis" != "None" ]; then
        log_info "デタッチ済みENI を削除中..."
        for eni_id in $avail_enis; do
            log_info "  削除: ${eni_id}"
            aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$region" 2>&1 || true
        done
    fi

    # 3. 非デフォルト Security Groups の削除（ROSA が VPC Endpoint 用に作成したもの等）
    local sg_ids
    sg_ids=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text --region "$region" 2>/dev/null || echo "")

    if [ -n "$sg_ids" ] && [ "$sg_ids" != "None" ]; then
        log_info "非デフォルト Security Groups を削除中..."
        for sg_id in $sg_ids; do
            log_info "  削除: ${sg_id}"
            aws ec2 delete-security-group --group-id "$sg_id" --region "$region" 2>&1 || true
        done
    fi

    # 結果サマリー
    local remaining_sgs
    remaining_sgs=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text --region "$region" 2>/dev/null || echo "")

    if [ -z "$remaining_sgs" ] || [ "$remaining_sgs" = "None" ]; then
        log_success "VPC内の孤立リソースをすべてクリーンアップしました"
    else
        log_warning "一部の Security Groups が残っています: ${remaining_sgs}"
        log_info "VPC削除時にリトライで解消される可能性があります"
    fi
}

# Terraform ディレクトリにローカル状態ファイルがあるか（このリポジトリはローカル state 前提）
terraform_dir_has_state_file() {
    local dir="$1"
    [ -f "${dir}/terraform.tfstate" ] || [ -f "${dir}/.terraform/terraform.tfstate" ]
}

# 指定スタックで terraform state list を実行（init が必要なら実施）
# 標準出力: アドレス一覧（空行区切りで複数）。終了コード 0=成功、1=失敗
terraform_state_list() {
    local dir="$1"
    pushd "$dir" > /dev/null || return 1
    if [ ! -d ".terraform" ]; then
        if ! terraform init -input=false -no-color >/dev/null 2>&1; then
            popd > /dev/null
            return 1
        fi
    else
        terraform init -input=false -no-color >/dev/null 2>&1 || true
    fi
    terraform state list -no-color 2>/dev/null
    local ec=$?
    popd > /dev/null
    return $ec
}

# 状態にリソースが残っている場合、destroy を 1 回だけ再試行
retry_terraform_destroy_in_dir() {
    local dir="$1"
    pushd "$dir" > /dev/null || return 1
    set +e
    terraform destroy -auto-approve -no-color 2>&1 | tee /tmp/terraform_destroy_retry_"$(basename "$dir")".log
    local ec=$?
    set -e
    popd > /dev/null
    return $ec
}

# クラウド側に該当リソースがもう無いのに state だけ残っているか（その場合のみ state rm してよい）
# 終了 0 = state のみ除去してよい、1 = クラウドに残骸がある可能性があるため state rm しない
should_prune_terraform_state_only() {
    local rel="$1"
    local cluster_name="$2"
    if [ "$rel" = "terraform/cluster" ]; then
        if check_rosa_cluster_still_exists "$cluster_name"; then
            return 1
        fi
        return 0
    fi
    if [ "$rel" = "terraform/network" ]; then
        if check_aws_vpc_tag_orphan "$cluster_name" >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi
    return 1
}

# 状態内の全アドレスを terraform state rm（クラウド側は既に無い前提）
terraform_state_rm_all_in_dir() {
    local dir="$1"
    local label="$2"
    pushd "$dir" > /dev/null || return 1
    terraform init -input=false -no-color >/dev/null 2>&1 || true
    local addrs
    addrs=$(terraform state list -no-color 2>/dev/null) || addrs=""
    if [ -z "$addrs" ]; then
        popd > /dev/null
        return 0
    fi
    set +e
    while IFS= read -r addr; do
        [ -z "$addr" ] && continue
        log_info "${label}: terraform state rm: ${addr}"
        terraform state rm -lock-timeout=300s -no-color "$addr" 2>&1
    done <<< "$addrs"
    set -e
    popd > /dev/null
    return 0
}

# ROSA に同名クラスターが残っていないか（参考情報）
check_rosa_cluster_still_exists() {
    local cluster_name="$1"
    if [ -z "$cluster_name" ]; then
        return 1
    fi
    if ! command -v rosa &>/dev/null; then
        return 1
    fi
    if rosa describe cluster -c "${cluster_name}" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# AWS 上にワークショップ用 VPC タグの VPC が残っていないか（Terraform 外の残骸のヒント）
check_aws_vpc_tag_orphan() {
    local cluster_name="${1:-}"
    local region="${AWS_DEFAULT_REGION:-ap-northeast-1}"
    if [ -z "$cluster_name" ] || ! command -v aws &>/dev/null; then
        return 1
    fi
    local vpc_ids
    vpc_ids=$(aws ec2 describe-vpcs \
        --region "$region" \
        --filters "Name=tag:Name,Values=${cluster_name}-vpc" \
        --query 'Vpcs[].VpcId' \
        --output text 2>/dev/null || echo "")
    if [ -n "$vpc_ids" ] && [ "$vpc_ids" != "None" ]; then
        echo "$vpc_ids"
        return 0
    fi
    return 1
}

# フェーズ終了後: Terraform 状態が空か、残存時は一覧表示と（通常時のみ）再 destroy 試行
# $1 = "read-only" のときは状態一覧とクラウド確認のみ（terraform destroy は実行しない）
verify_terraform_cleanup() {
    local readonly_mode=false
    if [ "${1:-}" = "read-only" ]; then
        readonly_mode=true
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "検証: Terraform 状態とクラウド上の残骸の確認"
    if [ "$readonly_mode" = true ]; then
        log_info "（読み取り専用: terraform destroy は実行しません）"
    fi
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local cluster_name="${TF_VAR_cluster_name:-}"
    if [ -z "$cluster_name" ]; then
        cluster_name=$(get_cluster_name 2>/dev/null || echo "")
    fi
    if [ -z "$cluster_name" ]; then
        cluster_name="mta-lightspeed"
    fi

    local tf_has_leftover=false

    for stack in "terraform/cluster:クラスター(ROSA)" "terraform/network:ネットワーク(VPC)"; do
        local rel="${stack%%:*}"
        local label="${stack##*:}"
        if [ ! -d "$SCRIPT_DIR/$rel" ]; then
            log_info "${label}: ディレクトリなし。スキップします"
            continue
        fi
        if ! terraform_dir_has_state_file "$SCRIPT_DIR/$rel"; then
            log_success "${label}: terraform state ファイルなし（未デプロイまたは既に削除済み）"
            continue
        fi

        local list
        list=$(terraform_state_list "$SCRIPT_DIR/$rel") || list=""
        if [ -z "$list" ]; then
            log_success "${label}: Terraform 状態は空です（リソースなし）"
            continue
        fi

        log_warning "${label}: Terraform 状態にリソースが残っています"
        while IFS= read -r addr; do
            [ -z "$addr" ] && continue
            echo "  - $addr"
        done <<< "$list"

        if [ "$readonly_mode" = true ]; then
            tf_has_leftover=true
            log_info "${label}: 手動で削除する場合の例:"
            echo "  cd $SCRIPT_DIR/$rel && terraform destroy -auto-approve"
            echo "  # 実リソースが既に無いのに state だけ残る場合: terraform state rm '<address>'"
        else
            log_info "${label}: 残存リソースの削除を再試行します（terraform destroy）..."
            retry_terraform_destroy_in_dir "$SCRIPT_DIR/$rel"
            list=$(terraform_state_list "$SCRIPT_DIR/$rel") || list=""
            if [ -z "$list" ]; then
                log_success "${label}: 再試行後、Terraform 状態は空になりました"
            else
                if [ "${DESTROY_NO_STATE_PRUNE:-}" != "1" ] && should_prune_terraform_state_only "$rel" "$cluster_name"; then
                    log_warning "${label}: クラウド上に該当リソースは見つかりませんでした。Terraform にだけ残っている参照を state から削除します（terraform state rm）"
                    terraform_state_rm_all_in_dir "$SCRIPT_DIR/$rel" "$label"
                    list=$(terraform_state_list "$SCRIPT_DIR/$rel") || list=""
                    if [ -z "$list" ]; then
                        log_success "${label}: terraform state rm により状態が空になりました"
                        continue
                    fi
                    log_warning "${label}: terraform state rm 後も状態にエントリが残っています"
                elif [ "${DESTROY_NO_STATE_PRUNE:-}" = "1" ] && should_prune_terraform_state_only "$rel" "$cluster_name"; then
                    log_info "${label}: クラウド上は該当リソースなしですが、DESTROY_NO_STATE_PRUNE=1 のため terraform state rm はスキップしました"
                elif ! should_prune_terraform_state_only "$rel" "$cluster_name"; then
                    log_warning "${label}: 再試行後も state にリソースが残っており、クラウド側にも残骸がある可能性があります（先にクラウドを削除してから再実行してください）"
                else
                    log_warning "${label}: 再試行後も状態にリソースが残っています"
                fi

                tf_has_leftover=true
                while IFS= read -r addr; do
                    [ -z "$addr" ] && continue
                    echo "  - $addr"
                done <<< "$list"
                log_info "${label}: 手動確認例:"
                echo "  cd $SCRIPT_DIR/$rel && terraform plan -destroy && terraform destroy"
                echo "  # 実リソースが既に無いのに state だけ残る場合: terraform state rm '<address>'"
            fi
        fi
    done

    local cloud_hint_dirty=0

    # 参考: ROSA CLI でクラスターがまだ見えるか
    if check_rosa_cluster_still_exists "$cluster_name"; then
        cloud_hint_dirty=1
        log_warning "ROSA 上にクラスター '${cluster_name}' がまだ存在します"
        log_info "確認: rosa describe cluster -c ${cluster_name}"
        log_info "削除: rosa delete cluster -c ${cluster_name} --yes（完了まで rosa logs uninstall -c ${cluster_name} --watch）"
    else
        log_info "ROSA: クラスター '${cluster_name}' は見つかりません（または rosa 未使用）"
    fi

    # 参考: 同名タグの VPC が AWS に残っていないか（state は空でも手動作成 VPC の可能性）
    local orphan_vpcs
    orphan_vpcs=$(check_aws_vpc_tag_orphan "$cluster_name" || true)
    if [ -n "$orphan_vpcs" ]; then
        cloud_hint_dirty=1
        log_warning "AWS に Name=${cluster_name}-vpc の VPC が残っています: ${orphan_vpcs}"
        log_info "VPC 内リソースを確認し、不要ならコンソールまたは aws CLI で削除してください"
    else
        log_info "AWS: タグ Name=${cluster_name}-vpc の VPC は検出されませんでした"
    fi

    if [ "$tf_has_leftover" = false ] && [ "$cloud_hint_dirty" -eq 0 ]; then
        log_success "検証: Terraform 状態は空で、主要なクラウド残骸も検出されませんでした"
        return 0
    fi
    if [ "$tf_has_leftover" = true ]; then
        log_warning "検証: Terraform 状態にまだリソースがあります。新規 deploy 前に解消してください"
    fi
    if [ "$cloud_hint_dirty" -ne 0 ]; then
        log_warning "検証: ROSA または AWS に名前付きリソースの残骸が見えます。必要に応じて手動で削除してください"
    fi
    return 1
}

# --verify-only 用: 削除せず検証のみ
run_verify_only() {
    print_banner
    check_prerequisites
    load_profile
    load_env_if_needed
    # ROSA / AWS 確認のため認証は推奨
    if ! command -v rosa &>/dev/null || rosa whoami >/dev/null 2>&1; then
        true
    else
        log_warning "ROSA に未ログインの可能性があります。クラスター存在確認は不正確になることがあります"
    fi
    if verify_terraform_cleanup "read-only"; then
        exit 0
    else
        exit 1
    fi
}

# メイン処理
main() {
    if [ "$VERIFY_ONLY" = true ]; then
        run_verify_only
    fi

    print_banner
    
    # ステップ1: 前提条件の確認
    check_prerequisites

    # ステップ1.5: プロファイル読み込み
    load_profile

    # ステップ1.6: env.sh の自動読み込み（認証情報）
    load_env_if_needed
    
    # ステップ2: ROSA認証の確認
    ensure_rosa_auth

    # ─── プロビジョナー検出 ───────────────────────────────────────────
    # 優先順位: --force-cluster-mode > メタデータファイル > ヒューリスティック > terraform
    local _provisioner=""

    if [ -n "$FORCE_CLUSTER_MODE" ]; then
        _provisioner="$FORCE_CLUSTER_MODE"
        log_info "クラスター削除方式（上書き）: ${_provisioner}（--force-cluster-mode）"
    else
        _provisioner=$(read_cluster_origin_provisioner)
        if [ -n "$_provisioner" ]; then
            log_info "クラスター削除方式（メタデータ検出）: ${_provisioner}"
            log_info "  参照: ${SCRIPT_DIR}/.mta-demo/cluster-origin.json"
        else
            # ヒューリスティック: terraform/cluster に state が無いのに ROSA にクラスターがある場合
            local _heuristic_name="${TF_VAR_cluster_name:-mta-lightspeed}"
            local _has_tf_state=false
            if [ -f "${SCRIPT_DIR}/terraform/cluster/terraform.tfstate" ] || \
               [ -f "${SCRIPT_DIR}/terraform/cluster/.terraform/terraform.tfstate" ]; then
                _has_tf_state=true
            fi

            if [ "$_has_tf_state" = false ] && \
               rosa describe cluster -c "${_heuristic_name}" > /dev/null 2>&1; then
                log_warning "ヒューリスティック検出: terraform/cluster に state がないが"
                log_warning "  ROSA 上にクラスター '${_heuristic_name}' が存在します（CLI 構築の可能性）"
                log_warning "  メタデータファイル (.mta-demo/cluster-origin.json) が見つかりません"
                echo ""
                echo "  クラスター削除方式を選択してください:"
                echo "    1) rosa-cli  (ROSA CLI で削除 / Terraform をスキップ)"
                echo "    2) terraform (Terraform destroy を試みる)"
                echo ""
                read -p "選択 [1/2、デフォルト: 1]: " -r _choice
                echo
                case "${_choice}" in
                    2) _provisioner="terraform" ;;
                    *) _provisioner="rosa-cli"  ;;
                esac
                log_info "選択されたクラスター削除方式: ${_provisioner}"
            else
                _provisioner="terraform"
                log_info "クラスター削除方式: terraform（デフォルト）"
            fi
        fi
    fi
    # ────────────────────────────────────────────────────────────────────

    # 削除確認（1回のみ）
    echo ""
    log_warning "⚠️  警告: この操作は以下のリソースを削除します："
    echo "  - ROSA HCPクラスター（方式: ${_provisioner}）"
    echo "  - VPC / サブネット / NAT Gateway などのネットワークリソース"
    if [ "$_provisioner" = "terraform" ]; then
        echo "  - 付随するすべてのTerraform管理リソース"
    fi
    echo ""
    read -p "本当に削除を続行しますか？ (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "削除をキャンセルしました"
        exit 0
    fi

    # ステップ3: フェーズ1 - ROSAクラスターの削除（方式により分岐）
    if [ "$_provisioner" = "rosa-cli" ]; then
        local _rosa_cluster_name
        _rosa_cluster_name=$(read_cluster_origin_name)
        destroy_cluster_rosa_cli "${_rosa_cluster_name}"
    else
        destroy_cluster
    fi

    # ステップ4: クラスター削除の完了確認（rosa logs uninstall --watch）
    wait_for_cluster_deletion

    # ステップ4.5: IAM ロール/OIDC を削除（Terraform/rosa-cli 両モード共通）
    # Terraform の rosa_hcp モジュールが作成した IAM Role も terraform destroy で
    # 消えきらない場合があるため、常にクリーンアップを実行する（冪等）
    local _iam_cluster_name
    _iam_cluster_name=$(read_cluster_origin_name)
    cleanup_iam_resources "${_iam_cluster_name}"

    # ステップ5: ENIのクリーンアップを待機
    wait_for_eni_cleanup

    # ステップ5.5: VPC内の孤立リソース（SG, VPC Endpoint等）を削除
    cleanup_vpc_orphaned_resources
    
    # ステップ6: フェーズ2 - ネットワークリソースの削除
    destroy_network
    
    # ステップ7: Terraform 状態とクラウド残骸の検証（空でない場合は一覧・再 destroy 試行）
    if [ "$SKIP_VERIFY" = true ]; then
        log_info "削除後の検証をスキップしました（--skip-verify）"
    else
        if ! verify_terraform_cleanup; then
            log_error "削除後の検証で問題が検出されました。ログを確認し、必要に応じて手動で残骸を削除してください。"
            exit 1
        fi
    fi

    # 完了メッセージ
    echo ""
    log_success "======================================"
    log_success "  環境削除が完了しました！"
    log_success "======================================"
    echo ""
    log_info "削除されたリソース："
    echo "  - ROSA HCPクラスター（フェーズ1、方式: ${_provisioner}）"
    echo "  - VPCとネットワークリソース（フェーズ2）"
    echo "  - すべての関連リソース"

    # メタデータファイルが残っている場合は削除する
    local _meta_file="${SCRIPT_DIR}/.mta-demo/cluster-origin.json"
    if [ -f "$_meta_file" ]; then
        rm -f "$_meta_file"
        log_info "クラスター起源メタデータを削除しました: ${_meta_file}"
    fi
    echo ""
    log_info "注意: AnsibleやGitOpsで作成されたOpenShiftリソースは"
    echo "      クラスター削除とともに自動的に削除されました"
    echo ""
    log_info "削除順序："
    echo "  1. ROSAクラスター（約10-20分）"
    echo "  2. ネットワークリソース（クラスター削除完了後）"
    echo ""
}

# スクリプト実行
main "$@"

