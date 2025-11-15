#!/bin/bash

###############################################################################
# ROSAトークン取得スクリプト
# 
# このスクリプトは rosa token コマンドを使用してトークンを取得し、
# Terraformプロバイダー用の環境変数に設定します。
###############################################################################

set -e

# カラー出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ROSA トークン取得スクリプト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ROSA CLIがインストールされているか確認
if ! command -v rosa &> /dev/null; then
    echo -e "${RED}エラー: rosa CLIがインストールされていません${NC}"
    echo "インストール方法: brew install rosa-cli"
    exit 1
fi

# ROSAにログインしているか確認
if ! rosa whoami > /dev/null 2>&1; then
    echo -e "${YELLOW}警告: ROSAにログインしていません${NC}"
    echo ""
    echo "まずログインしてください："
    echo "  ブラウザ環境: rosa login --use-auth-code"
    echo "  ブラウザレス環境: rosa login --use-device-code"
    exit 1
fi

# トークンを取得
echo "ROSAトークンを取得中..."
TOKEN=$(rosa token 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}エラー: トークンの取得に失敗しました${NC}"
    exit 1
fi

# 環境変数に設定
export RHCS_TOKEN="$TOKEN"

echo -e "${GREEN}✅ トークンを取得しました${NC}"
echo ""
echo "以下の環境変数が設定されました："
echo "  RHCS_TOKEN=${TOKEN:0:20}..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "使用方法："
echo ""
echo "1. 現在のシェルセッションで使用する場合："
echo "   source scripts/get-rosa-token.sh"
echo ""
echo "2. 環境変数を手動で設定する場合："
echo "   export RHCS_TOKEN=\$(rosa token)"
echo ""
echo "3. env.sh に追加する場合："
echo "   echo 'export RHCS_TOKEN=\$(rosa token)' >> env.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

