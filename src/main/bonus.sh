#!/bin/bash
# Bonus：start 时创建分离的 tmux 会话和采集器；stop 时正常停止采集器并结束会话。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-start}

source "$input/bonus.env"

process_stopped() {
    local state
    state=$(ps -o stat= -p "$1" 2>/dev/null || true)
    [ -z "$state" ] && return 0
    case "$state" in
        Z*) return 0 ;;
    esac
    return 1
}

terminate_and_wait() {
    local pid=$1 tries=${2:-50} i
    process_stopped "$pid" && return 0
    kill -TERM "$pid" 2>/dev/null || return 0
    for ((i = 0; i < tries; i++)); do
        process_stopped "$pid" && return 0
        sleep 0.1
    done
    return 1
}

# 从日志中的 START 行取回采集器 PID（tmux 里运行，脚本退出后仍然存活）。
collector_pid() {
    [ -f "$output/bonus.log" ] || return 1
    awk -v token="$TOKEN" '
        $1 == "START" && $2 == token { pid = $3 }
        END { if (pid == "") exit 1; sub(/^pid=/, "", pid); print pid }
    ' "$output/bonus.log"
}

if [ "$action" = "stop" ]; then
    pid=
    pid=$(collector_pid) || true
    if [ -n "$pid" ]; then
        terminate_and_wait "$pid" 50 || true
    fi
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION" 2>/dev/null || true
    exit 0
fi

# 用 %q 引用路径，tmux 交给 shell 执行时才能正确处理含空格的路径。
cmd="python3 $(printf '%q' "$WORKER_TOOL") --token $(printf '%q' "$TOKEN") --log $(printf '%q' "$output/bonus.log")"

tmux -L "$TMUX_SOCKET" new-session -d -s "$SESSION" "$cmd"
