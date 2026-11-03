#!/bin/bash
# ============================================================
# persist-www.sh —— /www 落盘到持久目录
# 沙箱/容器 rootfs 重置后 /www 会丢；宝塔硬编码 /www 路径，
# 用软链接把它的家安到工作区持久卷，数据天然免迁移。
# 用法: bash persist-www.sh   （可重复执行，幂等）
# ============================================================
exec > /tmp/persist_www.log 2>&1

WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
DATA="$WORK/bt_data/www"
sudo mkdir -p "$DATA"

if [ ! -L /www ] && [ -d /www ] && [ -n "$(sudo ls -A /www 2>/dev/null | head -1)" ]; then
    echo "检测到旧 /www 有数据，自动迁移到持久目录..."
    sudo cp -a /www/. "$DATA"/ && sudo rm -rf /www
fi
[ -L /www ] || sudo ln -s "$DATA" /www
echo "=== /www -> $(readlink /www) ==="
