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

# ---------- 生成站点导航页（动漫风格，用户自助看站点地址的唯一入口） ----------
gen_nav(){
  local panel_url; panel_url=$(get_panel_url)
  local list="" ptxt="" ptags=""
  [ -f "$WORK/ports.txt" ] && ptxt=$(tr '\n' ' ' < "$WORK/ports.txt")
  # 端口小标签（彩色圆角）
  for p in $ptxt; do
    ptags="$ptags<span style=\"display:inline-block;font-size:12px;color:#5b3a8e;background:linear-gradient(135deg,#ffe3f0,#e9ddff);border-radius:999px;padding:3px 10px;\">$p</span>"
  done
  if [ -f "$SITES" ]; then
    while IFS= read -r line; do
      port=$(echo "$line" | grep -oE '端口[0-9]+' | grep -oE '[0-9]+')
      url=$(echo "$line" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com')
      [ -n "$url" ] && list="$list<div style=\"display:flex;align-items:center;justify-content:space-between;background:#fff;border-radius:16px;padding:12px 14px;margin-bottom:10px;flex-wrap:wrap;gap:6px;box-shadow:0 4px 12px rgba(179,157,255,0.15);\"><span style=\"font-size:13px;font-weight:700;color:#5b3a8e;background:linear-gradient(135deg,#ffe3f0,#e9ddff);border-radius:999px;padding:4px 12px;\">站点 $port</span><a href=\"$url\" style=\"font-size:13px;color:#7a5cc0;text-decoration:none;word-break:break-all;font-weight:500;\">$url</a></div>"
    done < "$SITES"
  fi
  cat > $NAV <<EOF
<html style="margin:0;padding:0;">
<div style="box-sizing:border-box;max-width:540px;margin:0 auto;padding:20px 16px 28px;font-family:'PingFang SC','Hiragino Sans GB','Microsoft YaHei','Segoe UI',Arial,sans-serif;background:linear-gradient(160deg,#ffe9f2 0%,#f3e9ff 45%,#e6f2ff 100%);min-height:100vh;">
  <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;">
    <svg width="30" height="30" viewBox="0 0 24 24" style="flex:none;"><path fill="#ff9ecb" d="M12 2l2.9 6.2 6.8.8-5.1 4.6 1.4 6.7L12 17l-6 3.3 1.4-6.7L2.3 9l6.8-.8z"/><path fill="#fff" d="M12 6.5l1.3 2.8 3.1.4-2.3 2.1.6 3L12 13.3l-2.7 1.5.6-3-2.3-2.1 3.1-.4z"/></svg>
    <div>
      <div style="font-size:20px;font-weight:700;color:#5b3a8e;">我的服务器站点导航</div>
      <div style="font-size:12px;color:#9a7fc0;margin-top:2px;">新建站点后约 30 秒刷新本页，即可看到新站链接</div>
    </div>
  </div>

  <div style="background:linear-gradient(135deg,#ff9ecb,#b39dff);border-radius:20px;padding:14px 16px;margin:14px 0 18px;box-shadow:0 6px 18px rgba(179,157,255,0.35);">
    <div style="font-size:12px;color:rgba(255,255,255,0.92);margin-bottom:6px;display:flex;align-items:center;gap:6px;"><svg width="14" height="14" viewBox="0 0 24 24" style="flex:none;"><path fill="#fff" d="M12 21s-7-4.6-9.5-9C.8 8.8 3 5.5 6.4 5.5c2 0 3.6 1 4.6 2.6 1-1.6 2.6-2.6 4.6-2.6 3.4 0 5.6 3.3 3.9 6.5C19 16.4 12 21 12 21z"/></svg>宝塔面板</div>
    <a href="$panel_url" style="display:block;font-size:13px;color:#fff;font-weight:600;text-decoration:none;word-break:break-all;">$panel_url</a>
  </div>

  <div style="font-size:15px;font-weight:700;color:#5b3a8e;margin:0 0 10px 2px;">站点列表</div>
  $list

  <div style="background:#fff;border-radius:20px;padding:14px 16px;margin-top:16px;box-shadow:0 4px 14px rgba(179,157,255,0.18);">
    <div style="font-size:12px;color:#8a6fb8;line-height:1.9;">
      建站方法：面板 → 添加站点 → 域名填 <b style="color:#5b3a8e;">名字.后缀:端口</b>（如 test.com:20001）→ 确定<br>
      <span style="color:#5b3a8e;font-weight:600;">可用端口（30个，按顺序用）：</span>
    </div>
    <div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:8px;">
      $ptags
    </div>
    <div style="font-size:12px;color:#8a6fb8;margin-top:10px;">本页自动记录所有站点的公网访问地址，刷新即可查看。</div>
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
