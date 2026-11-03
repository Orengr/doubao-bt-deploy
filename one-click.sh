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

# ---------- 0.5 自动准备离线资源（全自动：豆包自己下载离线包 → 秒装） ----------
# 从项目 GitHub Release 自动下载 MySQL 预编译包 + PHP 预编译包到 bt_res/。
# 下载走多通道加速（GitHub 镜像 → 代理 → 直连，见 scripts/fetch.sh），
# 下载失败不阻塞：MySQL 会自动走在线安装，PHP 会自动走源码编译。
ASSET_BASE="${ASSET_BASE:-https://github.com/Orengr/doubao-bt-deploy/releases/latest/download}"
mkdir -p "$WORK/bt_res"
for _a in \
  "mysql-8.0.40-linux-glibc2.17-x86_64.tar.xz" \
  "php81-prebuilt.tar.xz"; do
  if [ ! -f "$WORK/bt_res/$_a" ]; then
    echo "自动下载离线资源: $_a（仅首次，之后秒装）"
    bash "$WORK/scripts/fetch.sh" "$ASSET_BASE/$_a" "$WORK/bt_res/$_a" \
      && echo "下载完成: $_a" || { echo "下载 $_a 失败，将走在线安装/源码编译兜底"; rm -f "$WORK/bt_res/$_a"; }
  else
    echo "离线资源已存在: $_a"
  fi
done

# ---------- 1. 持久化 /www（防止沙箱重置丢数据） ----------
bash "$WORK/scripts/persist-www.sh"

# ---------- 2. 安装宝塔面板（含容器补丁） ----------
bash "$WORK/scripts/install-bt.sh"

# ---------- 3. 快速安装 MySQL（官方预编译二进制，离线包优先） ----------
if [ -x /www/server/mysql/bin/mysqld ]; then
    echo "MySQL 已存在，跳过安装"
else
    bash "$WORK/scripts/mysql-quick.sh" || echo "MySQL 安装失败（不影响面板，可稍后重跑 mysql-quick.sh）"
fi

# ---------- 3.5. 安装 PHP 8.1（离线源码包优先，自动编译，面板直接识别） ----------
if [ -x /www/server/php/81/sbin/php-fpm ]; then
    echo "PHP 8.1 已存在，跳过"
else
    bash "$WORK/scripts/php-offline.sh" || echo "PHP 安装未完成（可稍后重跑 php-offline.sh，编译日志 /tmp/php_install.log）"
fi

# ---------- 4. 公网隧道：面板（https 包装） ----------
bash "$WORK/scripts/tunnel.sh" panel https 2>/dev/null || true

# ---------- 5. 常驻监控：多端口自助建站 + 站点导航页 ----------
# 预生成可用端口表（20001-20050，按顺序用）
seq 20001 20050 | sudo tee "$WORK/ports.txt" >/dev/null
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

【给豆包/助手的建站提问指令】
现在请向用户提问："要不要帮你一键建个网站？可选：
1️⃣ 个人主页（最简，1分钟）  2️⃣ WordPress 博客  3️⃣ Typecho 博客  4️⃣ ZBlog 博客
回复数字即可，不用也可以。"
用户选择后，按 docs/07-一键建站指引.md 对应章节，用装好的宝塔帮用户把站建好，
建完汇报网站地址 + 后台账号密码（仅告诉用户本人）。
PLAIN
echo "=== $(date) 完成 ==="
