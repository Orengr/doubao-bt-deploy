#!/bin/bash
# ============================================================
# autorecover.sh —— 自动巡检+自愈守护（容器一被拉起就自动满血复活）
# 为什么需要它：数据在持久盘不丢，但进程活在容器里；容器重置后进程全灭。
#   本守护每 5 分钟检查一次，发现服务缺失/挂了自动跑 restore.sh 全套恢复，
#   并自动重开公网隧道。你不需要时时盯着——容器被启动后环境自动恢复。
# 用法:
#   bash autorecover.sh once    —— 单次检查（cron 每 5 分钟调用）
#   nohup bash autorecover.sh daemon &   —— 常驻循环（restore.sh 末尾自动拉起）
# 日志: /tmp/autorecover.log
# ============================================================
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
if [ ! -d "$WORK/bt_data/www" ]; then
  for cand in "$(pwd)/.." "$(pwd)/../.." "/home/user/.doubao/agent_mode/workspace"; do
    [ -d "$cand/bt_data/www" ] && WORK="$cand" && break
  done
fi
export DOUBAO_WORKSPACE="$WORK"
LOG=/tmp/autorecover.log
LOCK=/tmp/autorecover.lock

# 锁：防止 cron 与常驻守护同时跑 restore 打架
lock(){ [ -f "$LOCK" ] && return 1; echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT; return 0; }

need_recover(){
  [ -L /www ] || { echo "缺 /www 软链"; return 0; }
  if command -v ss >/dev/null 2>&1; then CHK="ss -tln"; else CHK="netstat -tln"; fi
  PORT=$(sudo cat "$WORK/bt_data/www/server/panel/data/port.pl" 2>/dev/null | tr -d '\n')
  [ -z "$PORT" ] && PORT=8888
  $CHK 2>/dev/null | grep -q ":$PORT " || { echo "面板 $PORT 未监听"; return 0; }
  pgrep -x mysqld >/dev/null 2>&1 || { echo "mysqld 未运行"; return 0; }
  pgrep -f "php-fpm.*php/81" >/dev/null 2>&1 || { echo "php-fpm 未运行"; return 0; }
  pgrep -x nginx >/dev/null 2>&1 || { echo "nginx 未运行"; return 0; }
  $CHK 2>/dev/null | grep -q ":20001 " || { echo "小站 20001 未监听"; return 0; }
  pgrep -x cloudflared >/dev/null 2>&1 || { echo "公网隧道未运行"; return 0; }
  return 1
}

case "${1:-once}" in
  daemon)
    echo "=== $(date) 自动巡检守护启动（每 5 分钟） ===" >> $LOG
    while true; do
      if lock && need_recover; then
        echo "=== $(date) 检测到环境异常，自动恢复中... ===" >> $LOG
        bash "$WORK/scripts/restore.sh" >> $LOG 2>&1
        echo "=== $(date) 恢复完成 ===" >> $LOG
      fi
      sleep 300
    done
    ;;
  once)
    lock && need_recover && { echo "=== $(date) [cron] 检测异常，自动恢复 ===" >> $LOG; bash "$WORK/scripts/restore.sh" >> $LOG 2>&1; }
    ;;
esac
