#!/bin/bash
# Create S3 bucket for ODH-tool and OpenShift AI storage

set -euo pipefail

# 環境変数を読み込む
if [ -f "${SCRIPT_DIR:-}/../env.sh" ]; then
  source "${SCRIPT_DIR:-}/../env.sh"
fi

# AWSアカウントIDを取得
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="${TF_VAR_cluster_name:-mta-lightspeed}"
REGION="${TF_VAR_aws_region:-ap-northeast-1}"

# S3バケット名
BUCKET_NAME="${CLUSTER_NAME}-odh-storage-${AWS_ACCOUNT_ID}"

echo "Creating S3 bucket: ${BUCKET_NAME}"
echo "  Region: ${REGION}"
echo "  Cluster: ${CLUSTER_NAME}"

# バケットが既に存在するか確認
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists. Skipping creation."
else
  # バケット作成
  if [ "${REGION}" = "us-east-1" ]; then
    # us-east-1の場合はLocationConstraintを指定しない
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  echo "✅ Bucket ${BUCKET_NAME} created successfully"
fi

# パブリックアクセスブロック設定
echo "Setting public access block..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# タグ付け
echo "Setting tags..."
aws s3api put-bucket-tagging \
  --bucket "${BUCKET_NAME}" \
  --tagging "TagSet=[{Key=Purpose,Value=ODHStorage},{Key=Cluster,Value=${CLUSTER_NAME}}]"

echo ""
echo "✅ S3 bucket setup completed!"
echo "  Bucket: ${BUCKET_NAME}"
echo "  Region: ${REGION}"




