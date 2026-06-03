#!/usr/bin/env bash
###############################################################################
# terraform/cluster と terraform/network に溜まったローカル state バックアップを整理する
#
# Terraform は state 更新のたびに terraform.tfstate.<unixtime>.backup を作成します。
# 現在の terraform.tfstate が問題なければ、古いバックアップは削除してかまいません。
#
# 使い方:
#   ./scripts/prune-terraform-state-backups.sh          # 各ディレクトリで最新 5 件以外を削除
#   ./scripts/prune-terraform-state-backups.sh 10       # 最新 10 件を残す
#   DRY_RUN=1 ./scripts/prune-terraform-state-backups.sh  # 削除せず一覧だけ
#
# 注意: リモートバックエンド（S3 等）を使っている場合、このスクリプトはローカルファイルのみ対象です。
###############################################################################

set -euo pipefail

KEEP="${1:-5}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [ "$KEEP" -lt 0 ]; then
    echo "Usage: $0 [KEEP]" >&2
    echo "  KEEP: number of newest backup files to keep per terraform directory (default: 5)" >&2
    exit 1
fi

prune_in_dir() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    (
        cd "$dir" || exit 0
        shopt -s nullglob
        local files=(terraform.tfstate*.backup)
        ((${#files[@]} <= KEEP)) && return 0
        local sorted=()
        mapfile -t sorted < <(ls -t "${files[@]}" 2>/dev/null)
        local i
        for ((i = KEEP; i < ${#sorted[@]}; i++)); do
            local f="${sorted[i]}"
            if [ "$DRY_RUN" = "1" ]; then
                echo "[DRY-RUN] 削除予定: $dir/$f"
            else
                echo "削除: $dir/$f"
                rm -f "$f"
            fi
        done
    )
}

echo "各ディレクトリで最新 ${KEEP} 件の terraform.tfstate*.backup を残します（DRY_RUN=${DRY_RUN}）"
prune_in_dir "$ROOT/terraform/cluster"
prune_in_dir "$ROOT/terraform/network"
echo "完了"
