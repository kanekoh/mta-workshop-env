#!/bin/bash
###############################################################################
# 新しい環境プロファイルとGitOpsディレクトリ構造のスキャフォールド
#
# Usage:
#   ./scripts/create-env.sh <env-name>
#
# 生成されるもの:
#   profiles/<env-name>.env                    - プロファイル設定ファイル（雛形）
#   gitops/environments/<env-name>/apps/       - ArgoCD Application 配置先
#   gitops/environments/<env-name>/resources/  - 環境固有カスタムリソース配置先
#
# 生成後、Cursor AI に「この環境をカスタマイズして」と依頼すると
# プロファイルの変数埋めや Application YAML の配置を行ってくれます。
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# カラー出力
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# 引数チェック
if [ -z "${1:-}" ]; then
    echo "Usage: $0 <env-name>"
    echo ""
    echo "Examples:"
    echo "  $0 quarkus-workshop"
    echo "  $0 ai-inference"
    echo "  $0 demo-cluster"
    echo ""
    echo "Existing environments:"
    ls "$PROJECT_ROOT/gitops/environments/" 2>/dev/null | sed 's/^/  - /'
    echo ""
    echo "Existing profiles:"
    ls "$PROJECT_ROOT/profiles/"*.env 2>/dev/null | xargs -I{} basename {} .env | sed 's/^/  - /'
    exit 1
fi

ENV_NAME="$1"

# バリデーション
if [[ ! "$ENV_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Error: env-name must be lowercase alphanumeric with hyphens/underscores (e.g. 'my-workshop')" >&2
    exit 1
fi

PROFILE_FILE="$PROJECT_ROOT/profiles/${ENV_NAME}.env"
GITOPS_APPS_DIR="$PROJECT_ROOT/gitops/environments/${ENV_NAME}/apps"
GITOPS_RESOURCES_DIR="$PROJECT_ROOT/gitops/environments/${ENV_NAME}/resources"

# 既存チェック
if [ -f "$PROFILE_FILE" ]; then
    log_warning "プロファイル '${ENV_NAME}' は既に存在します: ${PROFILE_FILE}"
    read -p "上書きしますか？ (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "キャンセルしました"
        exit 0
    fi
fi

log_info "環境 '${ENV_NAME}' のスキャフォールドを作成中..."

# 1. プロファイル生成
log_info "プロファイル作成: ${PROFILE_FILE}"
cat > "$PROFILE_FILE" << EOF
#!/bin/bash
# Profile: ${ENV_NAME}
# TODO: この環境の説明を書いてください

PROFILE_NAME="${ENV_NAME}"
GITOPS_ENV="${ENV_NAME}"

# --- クラスター構成 ---
CLUSTER_VIA="terraform"
TF_VAR_rosa_machine_type="m6a.2xlarge"
TF_VAR_worker_pool_replicas="2"
TF_VAR_availability_zone_count="1"

# --- GPU ノードプール ---
# 空=""の場合は GPU ノードを追加しない
# 選択肢: g4dn.xlarge, g5.xlarge, g5.2xlarge, g6.xlarge, g6.2xlarge
GPU_MACHINE_TYPE=""
GPU_REPLICAS="0"

# --- Ansible 制御 ---
RUN_ANSIBLE="true"
# 実行する playbook をカンマ区切りで指定:
#   gitops        - OpenShift GitOps + App-of-Apps（ほぼ必須）
#   configmaps    - Operator RoleARN ConfigMap
#   tackle_secret - MTA Tackle の AI/LLM シークレット
#   odh_storage   - OpenShift AI 用 S3 バケット
#   loki_storage  - Loki 用 S3 バケット
ANSIBLE_PLAYBOOKS="gitops,configmaps"

# --- ワークショップユーザー ---
TF_VAR_admin_count="1"
TF_VAR_workshop_user_count="10"
EOF

# 2. GitOps ディレクトリ構造
log_info "GitOps ディレクトリ作成: ${GITOPS_APPS_DIR}"
mkdir -p "$GITOPS_APPS_DIR"
mkdir -p "$GITOPS_RESOURCES_DIR"

# apps/ に README を配置
cat > "$GITOPS_APPS_DIR/README.md" << EOF
# ${ENV_NAME} Environment - ArgoCD Applications

このディレクトリに ArgoCD Application YAML を配置すると、
App-of-Apps パターンで自動的にデプロイされます。

## 利用可能なオペレーター

以下から必要なものを \`gitops/environments/mta/apps/\` 等からコピーしてください:

| ファイル | オペレーター | 用途 |
|---------|------------|------|
| nfd-operator.yml | Node Feature Discovery | GPU ノード検出（GPU 使用時必須） |
| nvidia-operator.yml | NVIDIA GPU Operator | GPU ドライバー管理 |
| openshift-ai-operator.yml | OpenShift AI (RHOAI) | AI/ML プラットフォーム |
| authorino-operator.yml | Authorino | API 認証 |
| devspaces-operator.yml | Dev Spaces | クラウド IDE |
| cnpg-operator.yml | CloudNativePG | PostgreSQL |
| keycloak-operator.yml | Keycloak | ID 管理 |
| mta-operator.yml | MTA | アプリ移行ツール |
| loki-operator.yml | Loki | ログ収集 |
| network-observability-operator.yml | Network Observability | ネットワーク可視化 |

## Cursor AI での追加

Cursor に以下のように依頼できます:

  「${ENV_NAME} 環境に DevSpaces と Keycloak を追加して」

EOF

# resources/ に README を配置
cat > "$GITOPS_RESOURCES_DIR/README.md" << EOF
# ${ENV_NAME} Environment - Custom Resources

このディレクトリに環境固有のカスタムリソース YAML を配置します。
App-of-Apps の Application から参照されます。

例: Tackle CR, Keycloak Realm, DataScienceCluster 等
EOF

# 3. 完了メッセージ
echo ""
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "  環境 '${ENV_NAME}' のスキャフォールドを作成しました"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "生成されたファイル:"
echo "  - profiles/${ENV_NAME}.env"
echo "  - gitops/environments/${ENV_NAME}/apps/    (Application YAML 配置先)"
echo "  - gitops/environments/${ENV_NAME}/resources/ (カスタムリソース配置先)"
echo ""
echo "次のステップ:"
echo ""
echo "  1. プロファイルをカスタマイズ:"
echo "     vim profiles/${ENV_NAME}.env"
echo ""
echo "  2. 必要なオペレーターの Application YAML を配置:"
echo "     cp gitops/environments/mta/apps/devspaces-operator.yml \\"
echo "        gitops/environments/${ENV_NAME}/apps/"
echo ""
echo "  3. デプロイ:"
echo "     export PROFILE=\"${ENV_NAME}\""
echo "     source env.sh"
echo "     ./deploy.sh"
echo ""
echo "  または Cursor AI に依頼:"
echo "     「${ENV_NAME} 環境に必要なオペレーターを追加して」"
echo ""
