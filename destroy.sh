#!/bin/bash

###############################################################################
# MTA for Developer Lightspeed ワークショップ環境削除スクリプト
# 
# このスクリプトは以下を実行します：
# 1. Terraformを使用してROSA HCPクラスターを削除
# 2. rosaコマンドでクラスター削除の完了を確認
#
# オプション:
#   --log-file <file>    ログを指定ファイルに出力
#   -l, --log            ログをデフォルトファイル名で出力（destroy-YYYYMMDD-HHMMSS.log）
#   -h, --help           ヘルプを表示
#
# 環境変数:
#   DESTROY_LOG_FILE     ログファイルパス（--log-fileオプションで上書き可能）
###############################################################################

# スクリプトのディレクトリを取得（プロジェクトルートに移動）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ログファイル設定（環境変数から読み込み）
LOG_FILE="${DESTROY_LOG_FILE:-}"

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
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --log-file <file>    Log output to specified file
  -l, --log            Log output to default file (destroy-YYYYMMDD-HHMMSS.log)
  -h, --help           Show this help message

Environment Variables:
  DESTROY_LOG_FILE     Log file path (overridden by --log-file option)

Examples:
  $0 --log
  $0 --log-file my-destroy.log
  DESTROY_LOG_FILE=destroy.log $0
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
║  MTA for Developer Lightspeed Workshop Environment          ║
║  Red Hat OpenShift for AWS (ROSA) Cluster Destruction        ║
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
    
    # 方法1: Terraform outputから取得
    if terraform output -raw cluster_name > /dev/null 2>&1; then
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null)
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

# VPC内のENI（Elastic Network Interface）が削除されるまで待つ
wait_for_eni_cleanup() {
    log_info "VPC内のENI（Elastic Network Interface）のクリーンアップを待機中..."
    
    # VPC IDを取得
    pushd "$SCRIPT_DIR" > /dev/null || return 1
    pushd terraform/network > /dev/null || {
        popd > /dev/null
        return 1
    }
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    popd > /dev/null  # terraform/networkから戻る
    popd > /dev/null  # SCRIPT_DIRから戻る
    
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
        # VPC内のENIを確認（ROSA関連のENIは通常、Descriptionに特定のタグが含まれる）
        # または、attached状態のENIが0になるまで待つ
        ATTACHED_ENI_COUNT=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=in-use" \
            --query 'length(NetworkInterfaces)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$ATTACHED_ENI_COUNT" = "0" ] || [ -z "$ATTACHED_ENI_COUNT" ]; then
            log_success "VPC内のENIがクリーンアップされました"
            return 0
        fi
        
        log_info "ENI削除待機中... (残り: ${ATTACHED_ENI_COUNT}個のENI, 経過: ${ELAPSED}秒)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    log_warning "ENIのクリーンアップが完了しませんでした（タイムアウト: ${MAX_WAIT}秒）"
    log_info "残っているENIを確認してください："
    echo "  aws ec2 describe-network-interfaces --filters \"Name=vpc-id,Values=${VPC_ID}\" --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' --output table"
    return 0  # エラーとして扱わず、続行を許可
}

# メイン処理
main() {
    print_banner
    
    # ステップ1: 前提条件の確認
    check_prerequisites
    
    # ステップ1.5: env.shの自動読み込み（必要な場合）
    load_env_if_needed
    
    # ステップ2: ROSA認証の確認
    ensure_rosa_auth

    # 削除確認（1回のみ）
    echo ""
    log_warning "⚠️  警告: この操作は以下のリソースを削除します："
    echo "  - ROSA HCPクラスター"
    echo "  - VPC / サブネット / NAT Gateway などのネットワークリソース"
    echo "  - 付随するすべてのTerraform管理リソース"
    echo ""
    read -p "本当に削除を続行しますか？ (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "削除をキャンセルしました"
        exit 0
    fi
    
    # ステップ3: フェーズ1 - ROSAクラスターの削除
    destroy_cluster
    
    # ステップ4: クラスター削除の完了確認
    wait_for_cluster_deletion
    
    # ステップ5: ENIのクリーンアップを待機
    wait_for_eni_cleanup
    
    # ステップ6: フェーズ2 - ネットワークリソースの削除
    destroy_network
    
    # 完了メッセージ
    echo ""
    log_success "======================================"
    log_success "  環境削除が完了しました！"
    log_success "======================================"
    echo ""
    log_info "削除されたリソース："
    echo "  - ROSA HCPクラスター（フェーズ1）"
    echo "  - VPCとネットワークリソース（フェーズ2）"
    echo "  - すべての関連リソース"
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

