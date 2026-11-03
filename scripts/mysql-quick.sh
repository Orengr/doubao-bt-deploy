#!/bin/bash
# ============================================================
# mysql-quick.sh —— MySQL 8 快速安装（官方预编译二进制）
# 为什么快：源码编译要 1-2 小时；官方 glibc 预编译包解压即用，
# 全程 3-8 分钟。且同一 tar 包可拷贝到同架构其他机器直接用
# （用户问过"把别的机器装好的 MySQL 复制过来能不能直接用"——能，
#   本质就是把预编译目录拷过去，本脚本就是干这个的自动化版）。
#
# 用法: bash mysql-quick.sh [版本号]   （默认 8.0.40）
# 产物: /www/server/mysql + /etc/init.d/mysqld（开机自启脚本）
# root 密码: 随机生成，打印在日志 /tmp/mysql_quick.log 顶部
# ============================================================
exec > /tmp/mysql_quick.log 2>&1
set -e
echo "=== $(date) MySQL 快速安装开始 ==="

VER="${1:-8.0.40}"
ARCH="x86_64"
BASE="/www/server/mysql"
DATA="$BASE/data"
PKG="mysql-${VER}-linux-glibc2.17-${ARCH}.tar.xz"
# 下载顺序：GitHub Release（本项目预编译资产，走 fetch.sh 多通道加速，实测最快）
#          → 清华镜像 → MySQL 官方 CDN（国外源最慢，仅兜底）
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
ASSET_BASE="${ASSET_BASE:-https://github.com/Orengr/doubao-bt-deploy/releases/latest/download}"
URL="https://cdn.mysql.com/Downloads/MySQL-8.0/${PKG}"
TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-8.0/${PKG}"

# ---------- 0. 已有则跳过 ----------
if [ -x "$BASE/bin/mysqld" ]; then
    echo "MySQL 已存在: $BASE/bin/mysqld，跳过"
    exit 0
fi

# ---------- 1. 系统依赖（容器常见缺 libaio / libncurses） ----------
# 必须装 libaio1：缺了 mysqld --initialize 会直接失败（错误还被吞，排查半天）
sudo apt-get install -y libaio1 libaio-dev libnuma1 2>/dev/null || true
# libncurses5 在较新 Ubuntu（22.04+）没有包，用 libncurses6 替代
sudo apt-get install -y libncurses6 2>/dev/null || sudo apt-get install -y libncurses5 2>/dev/null || true
if ! ldconfig -p 2>/dev/null | grep -q 'libaio.so.1'; then
    echo "!! 缺少 libaio.so.1，尝试 apt-get update 后重装..."
    sudo apt-get update 2>/dev/null || true
    sudo apt-get install -y libaio1 libaio-dev || true
    if ! ldconfig -p 2>/dev/null | grep -q 'libaio.so.1'; then
        echo "!! libaio.so.1 仍缺失。MySQL 初始化必然失败。"
        echo "修复: sudo apt-get install -y libaio1  后重跑 bash mysql-quick.sh"
        exit 1
    fi
fi
echo "依赖检查通过（libaio.so.1 就绪）"

# ---------- 2. 取预编译包：离线包优先，没有才在线下载 ----------
cd /tmp
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_PKG=""
for cand in "$SCRIPT_DIR/bt_res/$PKG" "$SCRIPT_DIR/../bt_res/$PKG" "$WORK/bt_res/$PKG" "/tmp/$PKG"; do
  [ -f "$cand" ] && LOCAL_PKG="$cand" && break
done
if [ -n "$LOCAL_PKG" ]; then
  echo "找到离线包: $LOCAL_PKG（跳过下载，秒级解压）"
  cp -f "$LOCAL_PKG" /tmp/
else
  echo "无离线包，在线下载（约 800MB；优先 GitHub Release 多通道加速，实测最快）"
  if [ ! -f "$PKG" ]; then
      if bash "$SCRIPT_DIR/fetch.sh" "$ASSET_BASE/$PKG" "/tmp/$PKG"; then
          echo "GitHub Release 下载完成"
      else
          echo "GitHub Release 失败，尝试清华镜像..."
          curl -fSL -o "$PKG" "$TSINGHUA" || {
              echo "清华镜像失败，最后尝试官方 CDN（可能很慢）..."
              curl -fSL -o "$PKG" "$URL" || { echo "所有下载通道失败，请检查网络后重跑"; exit 1; }
          }
      fi
  fi
fi

# ---------- 3. 解压到 /www/server/mysql ----------
sudo mkdir -p "$BASE"
sudo tar -xf "$PKG" -C /tmp
sudo cp -a "/tmp/mysql-${VER}-linux-glibc2.17-${ARCH}/." "$BASE/"
sudo chown -R mysql:mysql "$BASE" 2>/dev/null || {
    sudo useradd -r -s /sbin/nologin mysql 2>/dev/null || true
    sudo chown -R mysql:mysql "$BASE"
}

# ---------- 4. 初始化数据目录（免密初始化，随后改密） ----------
# 错误不吞：初始化失败会打印详细原因到本日志 /tmp/mysql_quick.log
sudo mkdir -p "$DATA"
if ! sudo "$BASE/bin/mysqld" --initialize-insecure --basedir="$BASE" --datadir="$DATA" --user=mysql; then
    echo "!! MySQL 初始化失败（上面是详细错误，常见原因: 缺 libaio.so.1）"
    echo "修复: sudo apt-get install -y libaio1 后重跑 bash mysql-quick.sh"
    exit 1
fi

# ---------- 5. 开机自启脚本 ----------
sudo cp "$BASE/support-files/mysql.server" /etc/init.d/mysqld
sudo chmod +x /etc/init.d/mysqld

# ---------- 6. 启动并设置 root 随机密码 ----------
sudo /etc/init.d/mysqld start
sleep 3
ROOT_PW="BtMySql_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10)"
sudo "$BASE/bin/mysql" -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PW'; FLUSH PRIVILEGES;"

echo ""
echo "======== MySQL 安装完成 ========"
echo "版本: $VER"
echo "路径: $BASE"
echo "root 密码: $ROOT_PW   （请立即保存到自己的密码本，勿外传）"
echo "登录: $BASE/bin/mysql -uroot -p'$ROOT_PW'"
echo "================================="
