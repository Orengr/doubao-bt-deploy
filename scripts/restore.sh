#!/bin/bash
# ============================================================
# restore.sh —— 沙箱/容器重置后一键恢复
# 前提：持久目录里已有宝塔数据（bt_data/www），只需：
#   重建 /www 软链接 → 启动面板 → 启动 nginx/php/mysql → 起隧道 → 恢复站点监控
# 用法: bash restore.sh
# 日志: /tmp/bt_restore.log
# ============================================================
exec > /tmp/bt_restore.log 2>&1
echo "=== $(date) 开始恢复 ==="

WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
DATA="$WORK/bt_data/www"
CF="$WORK/cloudflared"

[ -d "$DATA/server/panel" ] || { echo "错误: 持久数据不存在 $DATA（先跑 one-click.sh）"; exit 1; }

# ---------- 1. 重建 /www 软链接 ----------
if [ ! -L /www ]; then
    sudo ln -s "$DATA" /www && echo "已重建 /www -> $DATA"
else
    echo "/www 已是软链接，跳过"
fi

# ---------- 2. 读取面板端口并启动 ----------
PORT=$(sudo cat "$DATA/server/panel/data/port.pl" 2>/dev/null | tr -d '\n')
[ -z "$PORT" ] && PORT=8888
echo "面板端口: $PORT"
sudo /etc/init.d/bt start 2>&1 | tail -3
for i in $(seq 1 30); do
    ss -tln 2>/dev/null | grep -q ":$PORT " && { echo "面板端口 $PORT 已就绪"; break; }
    sleep 2
done

# ---------- 3. 启动 Nginx / PHP-FPM / MySQL ----------
sudo /etc/init.d/nginx start >/dev/null 2>&1 || true
[ -x "$DATA/server/php/81/sbin/php-fpm" ] && sudo /etc/init.d/php-fpm-81 start >/dev/null 2>&1 || true
[ -x "$DATA/server/mysql/bin/mysqld" ] && sudo /etc/init.d/mysqld start >/dev/null 2>&1 || true
sleep 3

# ---------- 4. 公网隧道（cloudflared） ----------
[ -x "$CF" ] || curl -sL -o "$CF" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x "$CF"
pkill -f cloudflared 2>/dev/null || true
PORT=$PORT bash "$WORK/scripts/tunnel.sh" panel https 2>/dev/null || true
sleep 6
PORT=8088  bash "$WORK/scripts/tunnel.sh" web http  2>/dev/null || true

# ---------- 5. 恢复站点监控与导航页 ----------
sudo nohup bash "$WORK/scripts/sites-monitor.sh" > /tmp/sites_monitor.log 2>&1 &

echo ""
echo "================ 恢复完成 ================"
echo "面板: https://127.0.0.1:$PORT  公网: $(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/tunnel_panel.log 2>/dev/null | head -1)"
echo "默认站点:  http://127.0.0.1:8088 公网: $(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/tunnel_web.log 2>/dev/null | head -1)"
echo "导航页: 默认站点打开即是"
echo "=========================================="
echo ""
echo "重新生成汇报单（账号密码没变，网址可能更新）..."
bash "$WORK/scripts/summary.sh"
cat <<'PLAIN'

大白话说明：
- 你之前建的网站和数据库都还在（数据在持久目录里），放心；
- 控制台的网址可能变了（隧道地址是新的），看上面汇报单；
- 账号密码和之前一样，没变；
- 手机能打开：用汇报单里的"公网地址"。
PLAIN
