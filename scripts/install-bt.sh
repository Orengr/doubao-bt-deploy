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
set -o pipefail   # 面板安装失败必须中断，不能被 | tail 吞掉
echo "=== $(date) 开始安装宝塔 ==="

# ---------- 0. 免密 sudo 检查（容器 sudo 可能要密码，先探明再动手，避免中途卡死） ----------
if ! sudo -n true 2>/dev/null; then
    echo "!! 当前环境 sudo 需要密码，脚本无法自动执行系统级操作。"
    echo "   请任选其一："
    echo "   1) 以 root 身份运行： sudo -i 后  bash $0"
    echo "   2) 配置免密 sudo（编辑 /etc/sudoers 加 NOPASSWD:ALL）"
    echo "   若在豆包对话中被安全策略拦截，请按 docs/08-平台安全拦截与分步执行.md 分步手动执行"
    exit 1
fi



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
# 注意：sed 分隔符用 |（不能用 #，替换文本里含 # 会冲突报错）
if grep -q '\[ ! -f "/usr/bin/apt-get" \] && return 0' install_panel.sh; then
    sed -i 's|\[ ! -f "/usr/bin/apt-get" \] && return 0|return 0  # container patch|' install_panel.sh
    echo "补丁 2a 已应用"
else
    echo "补丁 2a 未命中（官方脚本可能已更新，跳过不影响安装）"
fi
# 2b. Apt_Ready: 容器内 apt-get update 无意义 -> 直接跳过
if grep -q '^Apt_Ready(){$' install_panel.sh; then
    sed -i '/^Apt_Ready(){$/{n;s|.*|    return 0  # container patch|;}' install_panel.sh
    echo "补丁 2b 已应用"
else
    echo "补丁 2b 未命中（官方脚本可能已更新，跳过不影响安装）"
fi

# ---------- 3. 安装（跳过交互确认 + 强制安装） ----------
# 注意：sudo 默认 env_reset 会丢弃环境变量，INSTALL_FORCE 必须在 sudo 内部 export
sudo bash -c 'export INSTALL_FORCE=true && cd /tmp && bash install_panel.sh -y ed8484bec'
echo "=== 面板安装退出码: $? ==="

# ---------- 4. 等面板就绪 ----------
PORT=$(grep -oE 'SERVER_IP:[0-9]+' /tmp/bt_install.log 2>/dev/null | tail -1 | cut -d: -f2)
[ -z "$PORT" ] && PORT=8888
echo "=== 面板端口: $PORT ==="
# ss 缺失时用 netstat 兜底（部分精简容器没装 iproute2）
if command -v ss >/dev/null 2>&1; then CHK="ss -tln"; else CHK="netstat -tln"; fi
for i in $(seq 1 30); do
    if $CHK 2>/dev/null | grep -q ":$PORT "; then
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
