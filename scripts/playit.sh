#!/bin/bash
# ============================================================
# playit.sh —— Playit.gg 固定域名隧道（账号绑定，可自动重连）
# 特点：
#   - 免费提供固定二级域名（如 xxx.playit.gg），不会像 trycloudflare
#     那样每次重启都变，环境重置后重跑本脚本就能回到同一个网址
#   - secret 存在持久目录，重置后自动读回来继续用
# 首次使用：
#   1. 注册 https://playit.gg/register（邮箱+密码，收验证码）
#   2. 登录后 Dashboard → Agents → Add Agent（选 Linux）→ 复制 secret
#   3. 把 secret 存到: <工作区>/playit/secret.txt
#   4. bash playit.sh
#   5. 打开控制台 → Tunnels → 添加隧道：本地端口填你网站的端口（如 20001）
#      → 会得到一个固定域名 xxx.playit.gg，手机/电脑随时可开
#   之后环境重置：直接再跑一次 restore.sh（会自动拉起本脚本），网址不变
# 用法: bash playit.sh
# 日志: /tmp/playit.log
# ============================================================
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
SECRET_FILE="$WORK/playit/secret.txt"
AGENT="$WORK/playit/playit"

# 没有 agent 就先下载（走 fetch.sh 多通道，避免直连 GitHub 卡死）
if [ ! -x "$AGENT" ]; then
    bash "$WORK/scripts/fetch.sh" \
        "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64" \
        "$AGENT" && chmod +x "$AGENT"
fi

# 没有 secret 就报错并给大白话指引
if [ ! -f "$SECRET_FILE" ]; then
    echo "错误: 找不到 $SECRET_FILE"
    echo "大白话: 去 https://playit.gg 注册个账号（邮箱就行），登录后点 Agents → Add Agent →"
    echo "选 Linux，复制那一长串 secret，把它单独存到上面这个文件里（只有那一串字符，不要多余内容）。"
    echo "弄好后再跑一次: bash playit.sh"
    exit 1
fi

SECRET=$(tr -d '\r\n ' < "$SECRET_FILE")
[ -z "$SECRET" ] && { echo "错误: $SECRET_FILE 是空的"; exit 1; }

# 杀掉旧的 playit（用 PID 全量，避免 pkill 自匹配自杀）
for p in $(pgrep -f "playit --secret" 2>/dev/null | grep -v "pgrep\|$$"); do
    [ -n "$p" ] && kill "$p" 2>/dev/null
done

sudo nohup "$AGENT" --secret "$SECRET" --socket-path /tmp/playit.sock > /tmp/playit.log 2>&1 &
sleep 3
if pgrep -f "playit --secret" >/dev/null 2>&1; then
    echo "✅ playit 已启动，连接中..."
    echo "下一步: 登录 playit.gg 控制台 → Tunnels → 添加隧道 → 本地端口填你网站的端口（如 20001）"
    echo "完成后控制台会显示固定域名 xxx.playit.gg，把域名记下来，以后重置跑 restore.sh 还是这个网址。"
else
    echo "启动失败，看日志: tail /tmp/playit.log"
    exit 1
fi
