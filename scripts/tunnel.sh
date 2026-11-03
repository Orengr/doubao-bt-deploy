#!/bin/bash
# ============================================================
# tunnel.sh —— 无公网 IP 的公网访问（内网穿透）
# 优先 cloudflared（trycloudflare 零配置），失败回退 serveo。
# 用法: bash tunnel.sh [名称] [http|https]  例如:
#   bash tunnel.sh panel https     # 面板（https 包装，防嗅探）
#   bash tunnel.sh web http        # 普通网站
# 地址输出到: /tmp/tunnel_<名称>.log
# ============================================================
set -e
NAME="${1:-web}"
SCHEME="${2:-http}"
CF="$(dirname "$0")/../cloudflared"
[ -n "$DOUBAO_WORKSPACE" ] && CF="$DOUBAO_WORKSPACE/cloudflared"
LOG="/tmp/tunnel_${NAME}.log"
URL="127.0.0.1:${PORT:-8888}"

# ---------- 0. 端口参数可外部覆盖 ----------
if [ -z "$PORT" ]; then
    case "$NAME" in
        panel) PORT=8888 ;;
        web)   PORT=8088 ;;
        *)     PORT=8088 ;;
    esac
fi
URL="127.0.0.1:$PORT"

# ---------- 1. 准备 cloudflared 二进制 ----------
if ! command -v cloudflared >/dev/null 2>&1; then
    if [ ! -x "$CF" ]; then
        bash "$(dirname "$0")/fetch.sh" \
            "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
            "$CF" && chmod +x "$CF"
    fi
fi
CMD=$(command -v cloudflared || echo "$CF")

# ---------- 2. 启动隧道 ----------
pkill -f "cloudflared.*$PORT" 2>/dev/null || true
nohup "$CMD" tunnel --url "$SCHEME://$URL" --no-autoupdate > "$LOG" 2>&1 &
echo "隧道启动(pid $!) -> $SCHEME://$URL"

# ---------- 3. 等待并打印地址 ----------
for i in $(seq 1 20); do
    ADDR=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | head -1)
    [ -n "$ADDR" ] && break
    sleep 2
done
if [ -n "$ADDR" ]; then
    echo "公网地址: $ADDR"
else
    echo "未取到地址，日志: $LOG（30 秒后重试或换 serveo）"
fi
