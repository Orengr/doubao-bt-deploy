#!/bin/bash
# ============================================================
# one-click.sh —— 豆包环境「一键宝塔 + 自助建站」总入口
# 适用：豆包工作区 / 各类 rootfs 易重置的容器（无 systemd、无公网 IP）
# 用法：bash one-click.sh
# 完成时打印：宝塔面板地址、面板登录信息、站点导航页地址
# 全过程日志：/tmp/bt_oneclick.log
# ============================================================
exec > /tmp/bt_oneclick.log 2>&1
set -e
echo "=== $(date) 一键部署开始 ==="

# ---------- 0. 工作区自适应（不写死任何人的路径） ----------
# 豆包工作区环境变量；兜底取当前目录
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
DATA="$WORK/bt_data/www"
CF="$WORK/cloudflared"
mkdir -p "$WORK"

echo "工作区: $WORK"

# ---------- 1. 持久化 /www（防止沙箱重置丢数据） ----------
bash "$WORK/scripts/persist-www.sh"

# ---------- 2. 安装宝塔面板（含容器补丁） ----------
bash "$WORK/scripts/install-bt.sh"

# ---------- 3. 快速安装 MySQL（官方预编译二进制，几分钟） ----------
if [ -x /www/server/mysql/bin/mysqld ]; then
    echo "MySQL 已存在，跳过安装"
else
    bash "$WORK/scripts/mysql-quick.sh" || echo "MySQL 安装失败（不影响面板，可稍后重跑 mysql-quick.sh）"
fi

# ---------- 4. 公网隧道：面板（https 包装） ----------
bash "$WORK/scripts/tunnel.sh" panel https 2>/dev/null || true

# ---------- 5. 常驻监控：多端口自助建站 + 站点导航页 ----------
# 预生成可用端口表（20001-20030，按顺序用）
seq 20001 20030 | sudo tee "$WORK/ports.txt" >/dev/null
sudo nohup bash "$WORK/scripts/sites-monitor.sh" > /tmp/sites_monitor.log 2>&1 &
echo "站点监控已启动（新站点约 30 秒自动出公网地址）"

# ---------- 6. 汇总输出 ----------
sleep 5
echo ""
echo "================ 部署完成，生成汇报单 ================"
# 汇总脚本把账号/密码/地址集中打印并保存到 /tmp/bt_summary.txt
bash "$WORK/scripts/summary.sh"
echo "======================================================="
cat <<'PLAIN'

接下来你只要做三件事（大白话版）：
1. 打开上面的控制台网址，用账号密码登录，第一件事去把密码改了；
2. 想建网站：登录控制台 → 点「网站」→「添加站点」→ 域名填「名字:端口」，
   比如 test.com:20001，确定即可。等 30 秒，导航页上就有你的网站地址了；
3. 手机访问：用汇报单里的"公网地址"，手机浏览器直接打开。
（完整大白话指令在 docs/05-傻瓜操作手册.md，可直接复制发给豆包）
PLAIN
echo "=== $(date) 完成 ==="
