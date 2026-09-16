#!/bin/bash
###############################################################################
# operator-resources.sh
#
# platform-ops 環境にデプロイされた Operator のリソース消費を一覧化する。
#   - DaemonSet: ノード数に比例するワークロード（別セクション）
#   - 非 DaemonSet: Deployment / StatefulSet（レプリカ数あり）
#
# 出力は Operator（namespace）ごとにグループ化し、コンテナ単位で
# CPU/Memory の requests / limits を表示する。
#
# 使い方:
#   ./scripts/operator-resources.sh
###############################################################################
set -eo pipefail

# ━━━ 対象 Operator 定義（配列で順序保持）━━━
OP_NAMES=(
  "RHACS"
  "ServiceMesh3"
  "Pipelines"
  "OADP"
  "ClusterLogging"
  "LokiOperator"
)
declare -A OP_NS=(
  ["RHACS"]="rhacs-operator"
  ["ServiceMesh3"]="openshift-operators"
  ["Pipelines"]="openshift-pipelines"
  ["OADP"]="openshift-adp"
  ["ClusterLogging"]="openshift-logging"
  ["LokiOperator"]="openshift-operators-redhat"
)
declare -A OP_LABEL=(
  ["RHACS"]=""
  ["ServiceMesh3"]="mesh|istio|sail|kiali"
  ["Pipelines"]=""
  ["OADP"]=""
  ["ClusterLogging"]=""
  ["LokiOperator"]=""
)

# ━━━ ヘルパー関数 ━━━
sep() { printf '%.0s─' {1..100}; echo; }

header() {
  echo ""
  sep
  printf "  %s\n" "$1"
  sep
}

# ━━━ メイン処理 ━━━
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║  Platform-Ops Operator リソース一覧                                                              ║"
echo "║  Cluster : $(oc whoami --show-server 2>/dev/null)"
echo "║  Date    : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "╚════════════════════════════════════════════════════════════════════════════════════════════════════╝"

# ---- ノード情報 ----
header "ノード情報"
printf "  %-55s %-14s %-6s %-14s\n" "NAME" "INSTANCE-TYPE" "vCPU" "MEMORY"
sep
oc get nodes --no-headers -o custom-columns=\
'NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,CPU:.status.capacity.cpu,MEM:.status.capacity.memory' 2>/dev/null | while IFS= read -r line; do
  printf "  %s\n" "$line"
done
NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "  ワーカーノード数: ${NODE_COUNT}"

# ════════════════════════════════════════════════
# セクション 1: DaemonSet 一覧
# ════════════════════════════════════════════════
header "【DaemonSet】 ノード数 × requests = クラスター全体の予約量"
printf "  %-32s %-24s %-5s %-10s %-10s %-10s %-10s\n" \
  "OPERATOR / DAEMONSET" "CONTAINER" "DES" "REQ_CPU" "REQ_MEM" "LIM_CPU" "LIM_MEM"
sep

for op in "${OP_NAMES[@]}"; do
  ns="${OP_NS[$op]}"
  filter="${OP_LABEL[$op]:-}"

  ds_json=$(oc get daemonsets -n "$ns" -o json 2>/dev/null || echo '{"items":[]}')
  ds_count=$(echo "$ds_json" | jq '.items | length')
  [[ "$ds_count" == "0" ]] && continue

  echo "$ds_json" | jq -r --arg filter "$filter" '
    .items[] |
    select(
      ($filter == "") or
      (.metadata.name | test($filter; "i"))
    ) |
    .metadata.name as $ds |
    .status.desiredNumberScheduled as $des |
    .spec.template.spec.containers[] |
    [$ds, .name, ($des|tostring),
     (.resources.requests.cpu // "-"),
     (.resources.requests.memory // "-"),
     (.resources.limits.cpu // "-"),
     (.resources.limits.memory // "-")] |
    @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r ds_name cname desired rcpu rmem lcpu lmem; do
    printf "  %-32s %-24s %-5s %-10s %-10s %-10s %-10s\n" \
      "[${op}] ${ds_name}" "$cname" "$desired" "$rcpu" "$rmem" "$lcpu" "$lmem"
  done
done

echo ""

# ════════════════════════════════════════════════
# セクション 2: Deployment / StatefulSet 一覧
# ════════════════════════════════════════════════
header "【Deployment / StatefulSet】 Operator 別 (レプリカ数付き)"
printf "  %-32s %-24s %-4s %-5s %-10s %-10s %-10s %-10s\n" \
  "OPERATOR / WORKLOAD" "CONTAINER" "KIND" "REPL" "REQ_CPU" "REQ_MEM" "LIM_CPU" "LIM_MEM"
sep

for op in "${OP_NAMES[@]}"; do
  ns="${OP_NS[$op]}"
  filter="${OP_LABEL[$op]:-}"
  printed_header=false

  for kind in deployments statefulsets; do
    short="Deploy"
    [[ "$kind" == "statefulsets" ]] && short="STS"

    res_json=$(oc get "$kind" -n "$ns" -o json 2>/dev/null || echo '{"items":[]}')
    count=$(echo "$res_json" | jq '.items | length')
    [[ "$count" == "0" ]] && continue

    echo "$res_json" | jq -r --arg filter "$filter" --arg kind "$short" '
      .items[] |
      select(
        ($filter == "") or
        (.metadata.name | test($filter; "i"))
      ) |
      .metadata.name as $wl |
      (.spec.replicas // 1) as $repl |
      .spec.template.spec.containers[] |
      [$wl, .name, $kind, ($repl|tostring),
       (.resources.requests.cpu // "-"),
       (.resources.requests.memory // "-"),
       (.resources.limits.cpu // "-"),
       (.resources.limits.memory // "-")] |
      @tsv
    ' 2>/dev/null | while IFS=$'\t' read -r wl_name cname wkind replicas rcpu rmem lcpu lmem; do
      if [[ "$printed_header" == "false" ]]; then
        echo ""
        printf "  ── %s (ns: %s) ──\n" "$op" "$ns"
        printed_header=true
      fi
      printf "  %-32s %-24s %-4s %-5s %-10s %-10s %-10s %-10s\n" \
        "$wl_name" "$cname" "$wkind" "$replicas" "$rcpu" "$rmem" "$lcpu" "$lmem"
    done
    # Subshell doesn't propagate printed_header, so re-check
  done
done

echo ""

# ════════════════════════════════════════════════
# セクション 3: 実測値 (oc adm top pods)
# ════════════════════════════════════════════════
header "【実測リソース】 oc adm top pods"
printf "  %-32s %-50s %-12s %-12s\n" \
  "OPERATOR" "POD" "CPU(cores)" "MEMORY"
sep

for op in "${OP_NAMES[@]}"; do
  ns="${OP_NS[$op]}"
  filter="${OP_LABEL[$op]:-}"

  top_output=$(oc adm top pods -n "$ns" --no-headers 2>/dev/null || true)
  [[ -z "$top_output" ]] && continue

  if [[ -n "$filter" ]]; then
    top_output=$(echo "$top_output" | grep -iE "$filter" || true)
    [[ -z "$top_output" ]] && continue
  fi

  while IFS= read -r line; do
    pod=$(echo "$line" | awk '{print $1}')
    cpu=$(echo "$line" | awk '{print $2}')
    mem=$(echo "$line" | awk '{print $3}')
    printf "  %-32s %-50s %-12s %-12s\n" "$op" "$pod" "$cpu" "$mem"
  done <<< "$top_output"
done

echo ""
sep
echo "  完了: $(date '+%Y-%m-%d %H:%M:%S %Z')"
sep
