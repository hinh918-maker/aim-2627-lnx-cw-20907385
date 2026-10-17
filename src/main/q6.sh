#!/bin/bash
# Q6：将本地 Debian 包安装到 output/sysroot，运行安装后的工具。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

root="$output/sysroot"
admindir="$root/var/lib/dpkg"

# dpkg 的私有数据库需要预先存在，否则非 root 下会报 status area 不可访问。
mkdir -p "$admindir/info" "$admindir/updates" "$admindir/triggers" \
    "$admindir/parts" "$admindir/alternatives"
[ -e "$admindir/status" ] || : > "$admindir/status"
[ -e "$admindir/available" ] || : > "$admindir/available"

dpkg --root="$root" --force-not-root --log=/dev/null -i "$input/aim-sentry-tools.deb"

"$root/usr/bin/aim-sentry-info" > "$output/tool-output.txt"
