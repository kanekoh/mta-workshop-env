#!/bin/bash
set -euo pipefail

###############################################################################
# HCP (Hosted Control Plane) Cluster Creation Script
#
# Prerequisites:
#   - MCE operator installed with hypershift/hypershift-local-hosting enabled
#   - AWS CLI configured with appropriate permissions
#   - oc CLI logged in to the hosting (management) cluster
#   - hcp CLI available (download from MCE ConsoleCLIDownload)
#
# Usage:
#   ./scripts/hcp-create-cluster.sh [prepare|create|destroy|status]
#
# Environment variables (set in env.sh or export before running):
#   HCP_CLUSTER_NAME    - Name for the hosted cluster (required)
#   HCP_BASE_DOMAIN     - Base domain for the hosted cluster (required)
#                         Tip: Red Hat Demo Platform の aws_route53_domain を利用すると
#                         DNS 委任が不要で扱いやすい
#   HCP_REGION          - AWS region (default: from hosting cluster)
#   HCP_NODE_REPLICAS   - Number of worker nodes (default: 2)
#   HCP_RELEASE_IMAGE   - OCP release image (optional, defaults to latest)
#   HCP_NAMESPACE       - Namespace for hosted cluster resources (default: clusters)
#   HCP_NETWORK_TYPE    - Network type: OVNKubernetes (default) or Other
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# env.sh may have unbound variables; temporarily disable -u
set +u
source "${PROJECT_ROOT}/env.sh" 2>/dev/null || true
set -u

HCP_CLUSTER_NAME="${HCP_CLUSTER_NAME:-}"
HCP_BASE_DOMAIN="${HCP_BASE_DOMAIN:-}"
HCP_REGION="${HCP_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo 'ap-northeast-1')}}"
HCP_NODE_REPLICAS="${HCP_NODE_REPLICAS:-2}"
HCP_RELEASE_IMAGE="${HCP_RELEASE_IMAGE:-}"
HCP_NAMESPACE="${HCP_NAMESPACE:-clusters}"
HCP_NETWORK_TYPE="${HCP_NETWORK_TYPE:-OVNKubernetes}"

S3_BUCKET_NAME="${HCP_CLUSTER_NAME}-oidc"
IAM_ROLE_NAME="${HCP_CLUSTER_NAME}-hcp-cli-role"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

validate_prerequisites() {
    local require_hcp="${1:-false}"
    local missing=0

    if [[ -z "${HCP_CLUSTER_NAME}" ]]; then
        log_error "HCP_CLUSTER_NAME is required"
        missing=1
    fi
    if [[ -z "${HCP_BASE_DOMAIN}" ]]; then
        log_error "HCP_BASE_DOMAIN is required"
        missing=1
    fi

    for cmd in aws oc; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [[ "${require_hcp}" == "true" ]]; then
        if ! command -v hcp &>/dev/null; then
            log_error "Required command not found: hcp"
            log_error "Download it from the cluster:"
            log_error "  oc get ConsoleCLIDownload hcp-cli-download -o jsonpath='{.spec.links[0].href}'"
            missing=1
        fi
    fi

    if [[ $missing -ne 0 ]]; then
        echo ""
        log_error "Missing prerequisites. Please set required variables and install tools."
        echo ""
        echo "  export HCP_CLUSTER_NAME=my-hosted-cluster"
        echo "  export HCP_BASE_DOMAIN=example.com"
        echo ""
        echo "  To get hcp CLI:"
        echo "    oc get ConsoleCLIDownload hcp-cli-download -o jsonpath='{.spec.links[0].href}'"
        exit 1
    fi
}

get_aws_account_id() {
    aws sts get-caller-identity --query Account --output text
}

#######################################
# Phase 1: Prepare AWS Resources
#######################################
prepare_aws_resources() {
    log_info "=== Preparing AWS resources for HCP ==="

    local account_id
    account_id=$(get_aws_account_id)
    log_info "AWS Account ID: ${account_id}"

    # 1. Create S3 bucket for OIDC
    log_info "Creating S3 bucket: ${S3_BUCKET_NAME} (region: ${HCP_REGION})"
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        log_warn "S3 bucket already exists: ${S3_BUCKET_NAME}"
    else
        if [[ "${HCP_REGION}" == "us-east-1" ]]; then
            aws s3api create-bucket \
                --bucket "${S3_BUCKET_NAME}" \
                --region "${HCP_REGION}"
        else
            aws s3api create-bucket \
                --bucket "${S3_BUCKET_NAME}" \
                --region "${HCP_REGION}" \
                --create-bucket-configuration LocationConstraint="${HCP_REGION}"
        fi

        aws s3api put-public-access-block \
            --bucket "${S3_BUCKET_NAME}" \
            --public-access-block-configuration \
                "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
    fi

    # Ensure bucket policy allows public read (required for OIDC discovery)
    log_info "Setting public read policy on S3 bucket"
    aws s3api put-bucket-policy --bucket "${S3_BUCKET_NAME}" --policy "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Sid\": \"AllowPublicRead\",
            \"Effect\": \"Allow\",
            \"Principal\": \"*\",
            \"Action\": \"s3:GetObject\",
            \"Resource\": \"arn:aws:s3:::${S3_BUCKET_NAME}/*\"
        }]
    }"

    # 2. Create IAM role for HCP CLI
    log_info "Creating IAM role: ${IAM_ROLE_NAME}"
    local trust_policy
    trust_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${account_id}:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warn "IAM role already exists: ${IAM_ROLE_NAME}"
    else
        aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document "${trust_policy}"

        aws iam attach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    fi

    # 3. Generate STS credentials file
    local sts_creds_file="${PROJECT_ROOT}/.hcp-sts-creds.json"
    log_info "Generating STS credentials: ${sts_creds_file}"

    local access_key="${AWS_ACCESS_KEY_ID:-}"
    local secret_key="${AWS_SECRET_ACCESS_KEY:-}"

    # Fall back to aws configure if env vars are empty
    if [[ -z "${access_key}" ]]; then
        access_key="$(aws configure get aws_access_key_id 2>/dev/null || true)"
    fi
    if [[ -z "${secret_key}" ]]; then
        secret_key="$(aws configure get aws_secret_access_key 2>/dev/null || true)"
    fi

    if [[ -z "${access_key}" || -z "${secret_key}" ]]; then
        log_error "AWS credentials not found in environment or ~/.aws/credentials"
        log_error "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or configure aws cli"
        exit 1
    fi

    cat > "${sts_creds_file}" <<EOF
{
    "region": "${HCP_REGION}",
    "aws_access_key_id": "${access_key}",
    "aws_secret_access_key": "${secret_key}"
}
EOF
    chmod 600 "${sts_creds_file}"

    # 4. Create OIDC S3 credentials secret on the cluster
    log_info "Creating OIDC S3 credentials secret on cluster"
    oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
        --namespace local-cluster \
        --from-literal=bucket="${S3_BUCKET_NAME}" \
        --from-literal=region="${HCP_REGION}" \
        --from-literal=credentials="$(printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' "${access_key}" "${secret_key}")" \
        --dry-run=client -o yaml | oc apply -f -

    log_info "=== AWS preparation complete ==="
    echo ""
    log_info "S3 Bucket:  ${S3_BUCKET_NAME}"
    log_info "IAM Role:   arn:aws:iam::${account_id}:role/${IAM_ROLE_NAME}"
    log_info "STS Creds:  ${sts_creds_file}"
    log_info "OIDC Secret: hypershift-operator-oidc-provider-s3-credentials (in local-cluster ns)"
}

#######################################
# Phase 2: Create Hosted Cluster
#######################################
create_hosted_cluster() {
    log_info "=== Creating Hosted Cluster: ${HCP_CLUSTER_NAME} ==="

    validate_prerequisites true

    local account_id
    account_id=$(get_aws_account_id)
    local sts_creds_file="${PROJECT_ROOT}/.hcp-sts-creds.json"
    local role_arn="arn:aws:iam::${account_id}:role/${IAM_ROLE_NAME}"

    # Ensure AWS credentials are available (from env.sh)
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "AWS credentials not available. Ensure env.sh exports AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
        exit 1
    fi
    export AWS_REGION="${HCP_REGION}"

    # Check pull secret exists before creating infra
    local pull_secret="${HCP_PULL_SECRET:-${PROJECT_ROOT}/pull-secret.txt}"
    if [[ ! -f "${pull_secret}" ]]; then
        # Try common alternative locations
        for alt in "${HOME}/.pull-secret.json" "${HOME}/pull-secret.txt" "${HOME}/Downloads/pull-secret.txt"; do
            if [[ -f "${alt}" ]]; then
                pull_secret="${alt}"
                break
            fi
        done
    fi
    if [[ ! -f "${pull_secret}" ]]; then
        log_error "Pull secret not found. Place it at: ${PROJECT_ROOT}/pull-secret.txt"
        log_error "Download from: https://console.redhat.com/openshift/install/pull-secret"
        log_error "Or set HCP_PULL_SECRET=/path/to/pull-secret.txt"
        exit 1
    fi

    # Generate STS credentials file in AWS SDK format (as output by 'aws sts get-session-token')
    log_info "Generating STS credentials file..."
    local sts_output
    sts_output=$(aws sts get-session-token --output json 2>&1) || {
        log_warn "get-session-token failed, using static credentials format"
        cat > "${sts_creds_file}" <<EOF
{
    "Credentials": {
        "AccessKeyId": "${AWS_ACCESS_KEY_ID}",
        "SecretAccessKey": "${AWS_SECRET_ACCESS_KEY}",
        "SessionToken": "",
        "Expiration": "2099-12-31T23:59:59Z"
    }
}
EOF
    }
    if [[ -n "${sts_output}" && "${sts_output}" == *"Credentials"* ]]; then
        echo "${sts_output}" > "${sts_creds_file}"
    fi
    chmod 600 "${sts_creds_file}"

    local cmd=(
        hcp create cluster aws
        --name "${HCP_CLUSTER_NAME}"
        --infra-id "${HCP_CLUSTER_NAME}"
        --base-domain "${HCP_BASE_DOMAIN}"
        --sts-creds "${sts_creds_file}"
        --pull-secret "${pull_secret}"
        --region "${HCP_REGION}"
        --generate-ssh
        --node-pool-replicas "${HCP_NODE_REPLICAS}"
        --namespace "${HCP_NAMESPACE}"
        --role-arn "${role_arn}"
        --network-type "${HCP_NETWORK_TYPE}"
    )

    if [[ -n "${HCP_RELEASE_IMAGE}" ]]; then
        cmd+=(--release-image "${HCP_RELEASE_IMAGE}")
    fi

    log_info "Running: ${cmd[*]}"
    "${cmd[@]}"

    log_info "=== Hosted Cluster creation initiated ==="
    echo ""
    log_info "Monitor progress:"
    echo "  oc -n ${HCP_NAMESPACE} get hostedcluster ${HCP_CLUSTER_NAME} -w"
    echo "  oc -n ${HCP_NAMESPACE} get nodepool -w"
    echo ""
    log_info "Get kubeconfig after completion:"
    echo "  oc extract secret/${HCP_CLUSTER_NAME}-admin-kubeconfig -n ${HCP_NAMESPACE} --to=-"
}

#######################################
# Status
#######################################
show_status() {
    log_info "=== HCP Status ==="

    echo ""
    log_info "HostedClusters:"
    oc get hostedclusters -A 2>/dev/null || log_warn "No HostedClusters found"

    echo ""
    log_info "NodePools:"
    oc get nodepools -A 2>/dev/null || log_warn "No NodePools found"

    echo ""
    log_info "Hypershift Operator:"
    oc get pods -n hypershift 2>/dev/null || \
    oc get pods -n multicluster-engine -l app=hypershift-operator 2>/dev/null || \
    log_warn "Hypershift operator pods not found"
}

#######################################
# Destroy Hosted Cluster
#######################################
destroy_hosted_cluster() {
    if [[ -z "${HCP_CLUSTER_NAME}" ]]; then
        log_error "HCP_CLUSTER_NAME is required"
        exit 1
    fi

    log_info "=== Destroying Hosted Cluster: ${HCP_CLUSTER_NAME} ==="
    log_warn "This will delete the hosted cluster and all associated AWS resources."
    read -p "Are you sure? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Cancelled."
        exit 0
    fi

    local account_id
    account_id=$(get_aws_account_id)
    local role_arn="arn:aws:iam::${account_id}:role/${IAM_ROLE_NAME}"

    # Ensure AWS credentials for destroy
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        log_error "AWS credentials not available."
        exit 1
    fi
    export AWS_REGION="${HCP_REGION}"

    hcp destroy cluster aws \
        --name "${HCP_CLUSTER_NAME}" \
        --namespace "${HCP_NAMESPACE}" \
        --sts-creds "${PROJECT_ROOT}/.hcp-sts-creds.json" \
        --infra-id "${HCP_CLUSTER_NAME}" \
        --role-arn "${role_arn}" \
        --base-domain "${HCP_BASE_DOMAIN}" \
        --region "${HCP_REGION}"

    log_info "Hosted Cluster destruction initiated."

    # Cleanup AWS resources
    log_info "Cleaning up AWS resources..."
    aws s3 rb "s3://${S3_BUCKET_NAME}" --force 2>/dev/null || true
    aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>/dev/null || true
    aws iam delete-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true
    oc delete secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster 2>/dev/null || true
    rm -f "${PROJECT_ROOT}/.hcp-sts-creds.json"

    log_info "=== Cleanup complete ==="
}

#######################################
# Main
#######################################
main() {
    local action="${1:-help}"

    case "${action}" in
        prepare)
            validate_prerequisites false
            prepare_aws_resources
            ;;
        create)
            create_hosted_cluster
            ;;
        status)
            show_status
            ;;
        destroy)
            destroy_hosted_cluster
            ;;
        help|*)
            echo "Usage: $0 [prepare|create|destroy|status]"
            echo ""
            echo "Commands:"
            echo "  prepare  - Create AWS resources (S3, IAM) and cluster secrets"
            echo "  create   - Create the hosted cluster via hcp CLI"
            echo "  destroy  - Destroy the hosted cluster and cleanup AWS resources"
            echo "  status   - Show current HCP status"
            echo ""
            echo "Required environment variables:"
            echo "  HCP_CLUSTER_NAME   - Name for the hosted cluster"
            echo "  HCP_BASE_DOMAIN    - Base domain (e.g. example.com)"
            echo "                       Tip: Red Hat Demo Platform の aws_route53_domain が便利"
            echo ""
            echo "Optional environment variables:"
            echo "  HCP_REGION         - AWS region (default: ap-northeast-1)"
            echo "  HCP_NODE_REPLICAS  - Worker node count (default: 2)"
            echo "  HCP_RELEASE_IMAGE  - OCP release image (default: latest)"
            echo "  HCP_NAMESPACE      - Namespace (default: clusters)"
            ;;
    esac
}

main "$@"
