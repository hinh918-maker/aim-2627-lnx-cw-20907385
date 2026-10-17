#!/bin/bash
# Q8：repair 时识别并停止采集器、修复 HTTP 服务；cleanup 时停止修复后的服务。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-repair}

source "$input/process.env"

# 已退出但父进程尚未回收的进程是僵尸，kill -0 仍会成功；
# 这里以进程状态判断是否真的不再运行，避免把僵尸误判为仍在运行。
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

if [ "$action" = "cleanup" ]; then
    if [ -f "$output/service/pid" ]; then
        service_pid=$(cat "$output/service/pid")
        terminate_and_wait "$service_pid" 50 || true
    fi
    exit 0
fi

mkdir -p "$output"

# -ww 避免 args 被截断；用数字 uid 再查用户名，避免 ps 的 user 列按 8 字符截断。
ps_line=$(ps -ww -o uid= -o stat= -o args= -p "$TARGET_PID")
proc_uid=$(printf '%s\n' "$ps_line" | awk '{print $1}')
proc_user=$(id -nu "$proc_uid")
proc_state=$(printf '%s\n' "$ps_line" | awk '{print $2}')
proc_cmd=$(printf '%s\n' "$ps_line" | awk '{for (i=3;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n")}')
{
    printf 'pid=%s\n' "$TARGET_PID"
    printf 'user=%s\n' "$proc_user"
    printf 'state=%s\n' "$proc_state"
    printf 'command=%s\n' "$proc_cmd"
} > "$output/process.txt"

cp "$WORKER_LOG" "$output/collector-sample.log"

terminate_and_wait "$TARGET_PID" || true

terminate_and_wait "$SERVICE_PID" || true

{
    printf 'bind=127.0.0.1\n'
    printf 'port=%s\n' "$TARGET_PORT"
    printf 'route=/status\n'
} > "$output/server.conf"

bash "$START_TOOL" "$output/server.conf" "$output/service"

status=""
for ((i = 0; i < 40; i++)); do
    status=$(curl -sS --noproxy '*' -m 2 \
        -o "$output/http-body.txt" \
        -w '%{http_code}' \
        "http://127.0.0.1:${TARGET_PORT}/status" 2>/dev/null || true)
    [ "$status" = "200" ] && break
    sleep 0.25
done
printf '%s\n' "$status" > "$output/http-status.txt"

exit 0
