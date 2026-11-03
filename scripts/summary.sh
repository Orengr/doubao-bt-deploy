#!/bin/bash
# ============================================================
# summary.sh —— 部署完成后汇总所有关键信息（账号/密码/地址）
# 把散落在各日志里的信息集中到 /tmp/bt_summary.txt 并打印，
# 供「豆包/助手执行完部署后」向用户汇报，也方便人手抄录。
# 用法: bash summary.sh
# ============================================================

WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
OUT=/tmp/bt_summary.txt

# ---------- 面板 ----------
PORT=$(cat /tmp/bt_panel_port 2>/dev/null || echo 8888)
# 面板默认账号密码：宝塔安装脚本输出 or default.pl
PANEL_USER=$(grep -aoE 'username: [^ ]+' /tmp/bt_install.log 2>/dev/null | tail -1 | cut -d' ' -f2)
[ -z "$PANEL_USER" ] && PANEL_USER=$(sudo cat /www/server/panel/data/user_info.json 2>/dev/null | grep -aoE '"username":"[^"]+"' | head -1 | cut -d'"' -f4)
[ -z "$PANEL_USER" ] && PANEL_USER="（见安装日志 /tmp/bt_install.log 或面板首页）"
PANEL_PASS=$(sudo cat /www/server/panel/default.pl 2>/dev/null | tr -d '\n')
[ -z "$PANEL_PASS" ] && PANEL_PASS="（见安装日志 /tmp/bt_install.log 或面板首页）"
PANEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/tunnel_panel.log 2>/dev/null | head -1)

# ---------- MySQL ----------
MYSQL_PW=$(grep -aoE 'root 密码: [^ ]+' /tmp/mysql_quick.log 2>/dev/null | tail -1 | sed 's/root 密码: //')
[ -z "$MYSQL_PW" ] && MYSQL_PW="（未安装或见 /tmp/mysql_quick.log）"

# ---------- 隧道 / 导航页 ----------
WEB_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/tunnel_web.log 2>/dev/null | head -1)
NAV_URL="${WEB_URL:-http://127.0.0.1:8088}"

cat > "$OUT" <<EOF
========================================
  豆包环境 · 一键部署完成汇报单
========================================
【1. 宝塔面板】
  本地地址 : https://127.0.0.1:${PORT}
  公网地址 : ${PANEL_URL:-（未起隧道，运行: PORT=$PORT bash scripts/tunnel.sh panel https）}
  登录账号 : $PANEL_USER
  登录密码 : $PANEL_PASS
  （登录成功后请立即修改默认密码）

【2. MySQL 8】
  安装路径 : /www/server/mysql
  root 密码: $MYSQL_PW
  （请立即保存到自己的密码本，勿外传）

【3. 站点导航页】
  本地地址 : http://127.0.0.1:8088
  公网地址 : $NAV_URL
  （所有站点端口->公网地址自动汇总在此页）

【4. 使用方法】
  建站: 面板 → 网站 → 添加站点 → 域名填 名字.后缀:端口（如 test.com:20001）→ 确定
  约 30 秒后刷新导航页即可看到新站公网地址。
  重置恢复: bash restore.sh

【4.1 新手建站·域名怎么填（大白话，直接讲给用户听）】
  “宝塔里那个『域名』框，不用填真的网址，随便编一个就行。
   格式就一句话：随便一个名字.随便一个后缀:导航页里的端口号。
   例子（照抄改名字就行）：
     test.com:20001
     myblog.net:20005
     wodezhan.top:20010
   意思是：前面『名字.后缀』是随便编的（test、myblog、wodezhan 都是编的，
   .com/.net/.top 也是随便选的，不存在也没关系）；
   后面冒号加的数字『端口号』才是关键——必须用导航页『可用端口』里列出来的，
   第一个站用 20001，第二个用 20002，按顺序用，不冲突。
   千万别加 http://，别加 www.，中间别留空格。填错会报错，删掉重填就行。”

【5. 安全提醒】
  面板默认密码与 MySQL root 密码均为本环境临时生成，
  首次登录请立即改密；trycloudflare 地址重启后会变。
========================================
EOF

cat "$OUT"
echo ""
echo "（以上内容已保存到: $OUT）"
