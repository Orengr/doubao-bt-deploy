#!/bin/bash
# ============================================================
# install-bt.sh —— 宝塔面板一键安装（容器环境补丁版）
# 适用：豆包/无 systemd 容器。官方安装脚本在容器里有 2 个死循环/卡死点：
#   1. Fix_Apt_Lock(): 容器内 /proc 全扫描死循环 → 跳过
#   2. Apt_Ready():   容器内 apt-get update 无意义且可能失败 → 跳过
# 用法: bash install-bt.sh
# ============================================================
exec > /tmp/bt_install.log 2>&1
set -e
echo "=== $(date) 开始安装宝塔 ==="

# ---------- 0. 先持久化 /www ----------
bash "$(dirname "$0")/persist-www.sh"

# ---------- 1. 下载官方安装脚本 ----------
cd /tmp
rm -f install_panel.sh
if [ -f /usr/bin/curl ]; then
    curl -sSO https://download.bt.cn/install/install_panel.sh
else
    wget -O install_panel.sh https://download.bt.cn/install/install_panel.sh
fi
[ -s install_panel.sh ] || { echo "下载安装脚本失败"; exit 1; }

# ---------- 2. Patch 容器不兼容点 ----------
# 2a. Fix_Apt_Lock: 容器内 /proc 全扫描死循环 -> 直接跳过
sed -i 's#\[ ! -f "/usr/bin/apt-get" \] && return 0#return 0  # container patch#' install_panel.sh
# 2b. Apt_Ready: 容器内 apt-get update 无意义 -> 直接跳过
sed -i '/^Apt_Ready(){$/{n;s/.*/    return 0  # container patch/;}' install_panel.sh

# ---------- 3. 安装（跳过交互确认 + 强制安装） ----------
# 注意：sudo 默认 env_reset 会丢弃环境变量，INSTALL_FORCE 必须在 sudo 内部 export
sudo bash -c 'export INSTALL_FORCE=true && cd /tmp && bash install_panel.sh -y ed8484bec'
echo "=== 面板安装退出码: $? ==="

# ---------- 4. 等面板就绪 ----------
PORT=$(grep -oE 'SERVER_IP:[0-9]+' /tmp/bt_install.log 2>/dev/null | tail -1 | cut -d: -f2)
[ -z "$PORT" ] && PORT=8888
echo "=== 面板端口: $PORT ==="
for i in $(seq 1 30); do
    if ss -tln 2>/dev/null | grep -q ":$PORT "; then
        echo "面板端口 $PORT 已就绪"
        break
    fi
    sleep 2
done

echo "=== 面板安装完成 $(date) ==="
echo "面板默认端口: $PORT"
echo "$PORT" > /tmp/bt_panel_port
echo "登录地址: https://127.0.0.1:$PORT"
echo "账号密码: 见面板首页输出 / www/server/panel/default.pl（首次登录强制改密）"
