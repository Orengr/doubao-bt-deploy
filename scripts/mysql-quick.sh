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
URL="https://cdn.mysql.com/Downloads/MySQL-8.0/${PKG}"

# ---------- 0. 已有则跳过 ----------
if [ -x "$BASE/bin/mysqld" ]; then
    echo "MySQL 已存在: $BASE/bin/mysqld，跳过"
    exit 0
fi

# ---------- 1. 系统依赖（容器常见缺 libaio / libncurses） ----------
sudo apt-get install -y libaio1 libncurses5 libncursesw5 libnuma1 2>/dev/null || true

# ---------- 2. 下载预编译包（CDN 失败可换清华/阿里镜像） ----------
cd /tmp
[ -f "$PKG" ] || curl -fSL -o "$PKG" "$URL" || {
    echo "官方 CDN 下载失败，尝试清华镜像..."
    curl -fSL -o "$PKG" "https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-8.0/${PKG}"
}

# ---------- 3. 解压到 /www/server/mysql ----------
sudo mkdir -p "$BASE"
sudo tar -xf "$PKG" -C /tmp
sudo cp -a "/tmp/mysql-${VER}-linux-glibc2.17-${ARCH}/." "$BASE/"
sudo chown -R mysql:mysql "$BASE" 2>/dev/null || {
    sudo useradd -r -s /sbin/nologin mysql 2>/dev/null || true
    sudo chown -R mysql:mysql "$BASE"
}

# ---------- 4. 初始化数据目录（免密初始化，随后改密） ----------
sudo mkdir -p "$DATA"
sudo "$BASE/bin/mysqld" --initialize-insecure --basedir="$BASE" --datadir="$DATA" --user=mysql 2>/dev/null || \
sudo "$BASE/bin/mysqld" --initialize-insecure --basedir="$BASE" --datadir="$DATA" 2>/dev/null || {
    echo "初始化失败，检查依赖: sudo apt-get install -y libaio1"; exit 1;
}

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
