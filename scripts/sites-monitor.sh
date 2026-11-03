#!/bin/bash
# ============================================================
# sites-monitor.sh —— 多端口自助建站 + 站点导航页（常驻）
# 功能：
#   1. 扫描宝塔 nginx 站点配置，发现新站点端口自动起 cloudflared 隧道
#   2. 把「端口 -> 公网地址」写入 sites.txt
#   3. 自动生成"我的服务器站点导航"页（默认站点根目录 index.html）
#      新站点约 20-30 秒出现在导航页上；删除站点自动关隧道并同步导航页
# 用法: sudo nohup bash sites-monitor.sh &
# ============================================================
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
CLOUD="$WORK/cloudflared"
[ -x "$CLOUD" ] || CLOUD=$(command -v cloudflared || echo cloudflared)
LOGDIR="$WORK/sites_tunnels"
SITES="$WORK/sites.txt"
NAV=/www/wwwroot/default/index.html          # 导航页（面板默认站点）
PANEL_PORT="${PANEL_PORT:-8888}"
mkdir -p "$LOGDIR"

# 面板隧道地址（由 tunnel.sh panel 生成，未取到则显示本地地址）
get_panel_url(){
  local u
  u=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/tunnel_panel.log 2>/dev/null | head -1)
  if [ -n "$u" ]; then
    echo "$u"
  else
    echo "https://127.0.0.1:$PANEL_PORT（未起面板隧道，运行: PORT=$PANEL_PORT bash scripts/tunnel.sh panel https）"
  fi
}

# ---------- 生成站点导航页（用户自助看站点地址的唯一入口） ----------
gen_nav(){
  local panel_url; panel_url=$(get_panel_url)
  local list="" ptxt=""
  [ -f "$WORK/ports.txt" ] && ptxt=$(tr '\n' ' ' < "$WORK/ports.txt")
  if [ -f "$SITES" ]; then
    while IFS= read -r line; do
      port=$(echo "$line" | grep -oE '端口[0-9]+' | grep -oE '[0-9]+')
      url=$(echo "$line" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com')
      [ -n "$url" ] && list="$list<div style=\"display:flex;align-items:center;justify-content:space-between;background:#fff;border:1px solid rgba(0,0,0,0.08);border-radius:12px;padding:12px 14px;margin-bottom:8px;flex-wrap:wrap;gap:6px;\"><span style=\"font-size:14px;font-weight:600;color:#1A1B1C;\">站点 $port</span><a href=\"$url\" style=\"font-size:13px;color:#1a73e8;text-decoration:none;word-break:break-all;\">$url</a></div>"
    done < "$SITES"
  fi
  cat > $NAV <<EOF
<html style="margin:0;padding:0;">
<div style="box-sizing:border-box;max-width:520px;margin:0 auto;padding:16px;font-family:'Roboto','PingFang SC','Segoe UI',Arial,sans-serif;background:#F4F3EE;min-height:100vh;">
  <div style="font-size:18px;font-weight:600;color:#1A1B1C;margin-bottom:4px;">我的服务器站点导航</div>
  <div style="font-size:12px;color:#6B7280;margin-bottom:16px;">新建站点后约 30 秒刷新本页，即可看到新站链接</div>

  <div style="font-size:13px;color:#1A1B1C;background:linear-gradient(135deg,rgba(139,200,234,0.2),rgba(139,200,234,0.34));border-radius:12px;padding:12px 14px;margin-bottom:16px;">
    <b>宝塔面板：</b><a href="$panel_url" style="color:#1a73e8;word-break:break-all;">$panel_url</a>
  </div>

  <div style="font-size:14px;font-weight:600;color:#1A1B1C;margin-bottom:8px;">站点列表</div>
  $list

  <div style="font-size:12px;color:#6B7280;margin-top:16px;line-height:1.6;">
    建站方法：面板 → 添加站点 → 域名填 <b>名字.后缀:端口</b>（如 test.com:20001）→ 确定<br>
    可用端口（30个，按顺序用）：$ptxt<br>
    本页自动记录所有站点的公网访问地址，刷新即可查看。
  </div>
</div>
</html>
EOF
  chmod 644 $NAV 2>/dev/null
  echo "导航页已更新: $NAV"
}

# ---------- 恢复历史 端口->URL 映射 ----------
declare -A MAP
for f in $LOGDIR/site_*.log; do
  [ -f "$f" ] || continue
  port=$(basename "$f" .log | sed 's/site_//')
  url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$f" | head -1)
  [ -n "$url" ] && MAP[$port]=$url
done

gen_nav

# ---------- 主循环 ----------
while true; do
  active=""
  for conf in /www/server/panel/vhost/nginx/*.conf; do
    [ -f "$conf" ] || continue
    base=$(basename "$conf" .conf)
    [ "$base" = "default" ] && continue
    [ "$base" = "phpfpm_status" ] && continue
    case "$base" in 0.*) continue;; esac
    port=$(sudo grep -E '^\s*listen\s+[0-9]+' "$conf" 2>/dev/null | head -1 | grep -oE '[0-9]+')
    [ -z "$port" ] && continue
    [ "$port" = "80" ] && continue
    [ "$port" = "8088" ] && continue
    active="$active $port"
    if ! ps -eo args | grep -qE "cloudflared.*127\.0\.0\.1:$port"; then
      nohup $CLOUD tunnel --url http://127.0.0.1:$port --no-autoupdate > $LOGDIR/site_$port.log 2>&1 &
      url=""
      for i in $(seq 1 20); do
        url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' $LOGDIR/site_$port.log 2>/dev/null | head -1)
        [ -n "$url" ] && break
        sleep 2
      done
      if [ -n "$url" ]; then
        MAP[$port]=$url
        grep -qE "端口$port" $SITES 2>/dev/null || echo "$(date '+%F %T') 端口$port -> $url" >> $SITES
        gen_nav
      fi
    fi
  done

  # ---------- 删除同步 ----------
  if [ -f "$SITES" ]; then
    changed=""
    while IFS= read -r line; do
      port=$(echo "$line" | grep -oE '端口[0-9]+' | grep -oE '[0-9]+')
      [ -z "$port" ] && continue
      if ! echo "$active" | grep -qE "(^| )$port( |$)"; then
        sudo pkill -f "cloudflared.*127\.0\.0\.1:$port" 2>/dev/null
        rm -f $LOGDIR/site_$port.log
        unset MAP[$port]
        sudo sed -i "/端口$port/d" $SITES
        changed="1"
      fi
    done < "$SITES"
    [ -n "$changed" ] && gen_nav
  fi
  sleep 20
done
