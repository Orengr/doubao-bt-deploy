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

# ---------- 2. 重建系统用户（重置会把 mysql/www 用户清掉） ----------
# 先看持久数据的属主 uid，再按同样 uid 重建，避免数据属主对不上
DATA_MYSQL_UID=$(sudo stat -c %u "$DATA/server/mysql/data" 2>/dev/null | tr -d '\n')
DATA_WWW_UID=$(sudo stat -c %u "$DATA/wwwroot" 2>/dev/null | tr -d '\n')
[ -z "$DATA_MYSQL_UID" ] && DATA_MYSQL_UID=1236
[ -z "$DATA_WWW_UID" ] && DATA_WWW_UID=1235
if ! getent passwd mysql >/dev/null 2>&1; then
    sudo useradd -r -s /sbin/nologin -u "$DATA_MYSQL_UID" mysql 2>/dev/null         || sudo useradd -r -s /sbin/nologin mysql 2>/dev/null
    echo "已重建 mysql 用户 (uid=$DATA_MYSQL_UID)"
fi
if ! getent passwd www >/dev/null 2>&1; then
    # 若 www 的 uid 被 mysql 占了，就先建普通 uid 再对齐属主
    sudo useradd -r -s /sbin/nologin -u "$DATA_WWW_UID" www 2>/dev/null         || sudo useradd -r -s /sbin/nologin www 2>/dev/null
    echo "已重建 www 用户 (uid=$DATA_WWW_UID)"
fi

# ---------- 3. 依赖库检查修复（重置会把运行时库清掉，实测踩过） ----------
fix_apt(){ sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y "$@" >/dev/null 2>&1; }
# 3.1 libaio（MySQL 必须，缺了直接起不来且初始化失败）
ldconfig -p | grep -q libaio.so.1 || { echo "缺 libaio.so.1，安装中..."; fix_apt libaio1 || echo "apt 装不了，手动: sudo dpkg -i 下载的 libaio1_*.deb"; }
# 3.2 libssl1.1（PHP 8.1 预编译版链的是 OpenSSL 1.1）
ldconfig -p | grep -q "libssl.so.1.1" || { echo "缺 libssl.so.1.1，安装中..."; fix_apt libssl1.1 || echo "apt 装不了（Ubuntu 22.04 需从 focal 仓库下载 libssl1.1_1.1.1f-*.deb）"; }
# 3.3 libncurses.so.5（mysql 命令行客户端需要；22.04 只有 6，软链兼容）
ldconfig -p | grep -q libncurses.so.5 || { echo "缺 libncurses.so.5，用 6 软链兼容..."; sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5; sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/libtinfo.so.5; }
# 3.4 libzip4（php zip 扩展需要；装不上就禁用该扩展，不影响网站功能）
ldconfig -p | grep -q libzip.so.4 || { echo "缺 libzip.so.4，安装中..."; fix_apt libzip4; }
# 3.5 libluajit 符号（宝塔 nginx 需要 lua_getexdata，系统包没有这个符号 → 编译 OpenResty 版）
if ! nm -D /lib/x86_64-linux-gnu/libluajit-5.1.so.2 2>/dev/null | grep -q lua_getexdata; then
    echo "系统 libluajit 缺 lua_getexdata 符号（宝塔 nginx 起不来），编译 OpenResty 版（约 1 分钟）..."
    bash "$WORK/scripts/fetch.sh" "https://github.com/openresty/luajit2/archive/refs/tags/v2.1-20240815.tar.gz" /tmp/luajit2.tar.gz
    cd /tmp && tar -xf luajit2.tar.gz && cd luajit2-2.1-20240815
    sudo make -j4 PREFIX=/usr/local >/tmp/luajit_build.log 2>&1
    sudo make install PREFIX=/usr/local >>/tmp/luajit_build.log 2>&1
    sudo cp /usr/local/lib/libluajit-5.1.so.2 /lib/x86_64-linux-gnu/libluajit-5.1.so.2
    sudo ldconfig
    echo "libluajit 已替换为 OpenResty 版"
fi

# ---------- 4. 重建 init 脚本（重置会把 /etc/init.d 里的服务脚本清掉） ----------
# 4.1 mysqld
if [ ! -f /etc/init.d/mysqld ] && [ -f "$DATA/server/mysql/support-files/mysql.server" ]; then
    sudo cp "$DATA/server/mysql/support-files/mysql.server" /etc/init.d/mysqld
    sudo chmod +x /etc/init.d/mysqld
    echo "已重建 /etc/init.d/mysqld"
fi
# 4.2 php-fpm-81
if [ ! -f /etc/init.d/php-fpm-81 ] && [ -x "$DATA/server/php/81/sbin/php-fpm" ]; then
    sudo tee /etc/init.d/php-fpm-81 >/dev/null <<'INIT'
#!/bin/bash
prefix=/www/server/php/81
php_fpm_BIN=${prefix}/sbin/php-fpm
php_fpm_CONF=${prefix}/etc/php-fpm.conf
php_fpm_PID=${prefix}/var/run/php-fpm.pid
case "$1" in
  start)
    echo "Starting php-fpm-81 ..."
    mkdir -p ${prefix}/var/run
    chown -R www:www ${prefix}/var 2>/dev/null
    $php_fpm_BIN --fpm-config $php_fpm_CONF --pid $php_fpm_PID
    ;;
  stop)
    [ -f $php_fpm_PID ] && kill "$(cat $php_fpm_PID)" 2>/dev/null
    ;;
  restart)
    $0 stop; sleep 1; $0 start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"; exit 1
    ;;
esac
exit 0
INIT
    sudo chmod +x /etc/init.d/php-fpm-81
    echo "已重建 /etc/init.d/php-fpm-81"
fi
# 4.3 php.ini zip 扩展兼容（zip.so 和系统 libzip 版本符号不匹配会让 php-fpm 整体起不来 → 禁用）
if [ -f "$DATA/server/php/81/etc/php.ini" ]; then
    if sudo "$DATA/server/php/81/sbin/php-fpm" --fpm-config "$DATA/server/php/81/etc/php-fpm.conf" --test 2>&1 | grep -q "zip_libzip_version"; then
        sudo sed -i 's|^extension[[:space:]]*=[[:space:]]*zip\.so|;extension = zip.so|' "$DATA/server/php/81/etc/php.ini"
        echo "zip 扩展版本不兼容，已禁用（不影响网站功能）"
    fi
fi

# ---------- 5. 读取面板端口并启动 ----------
PORT=$(sudo cat "$DATA/server/panel/data/port.pl" 2>/dev/null | tr -d '\n')
[ -z "$PORT" ] && PORT=8888
echo "面板端口: $PORT"
sudo /etc/init.d/bt start 2>&1 | tail -3
if command -v ss >/dev/null 2>&1; then CHK="ss -tln"; else CHK="netstat -tln"; fi
for i in $(seq 1 30); do
    $CHK 2>/dev/null | grep -q ":$PORT " && { echo "面板端口 $PORT 已就绪"; break; }
    sleep 2
done

# ---------- 6. 启动 Nginx / PHP-FPM / MySQL ----------
sudo /etc/init.d/nginx start >/dev/null 2>&1 || true
[ -x "$DATA/server/php/81/sbin/php-fpm" ] && sudo /etc/init.d/php-fpm-81 start >/dev/null 2>&1 || true
[ -x "$DATA/server/mysql/bin/mysqld" ] && sudo /etc/init.d/mysqld start >/dev/null 2>&1 || true
sleep 3



# ---------- 7. 公网隧道（cloudflared，走 fetch.sh 多通道加速，避免直连 GitHub 卡死） ----------
if [ ! -x "$CF" ] && ! command -v cloudflared >/dev/null 2>&1; then
    bash "$WORK/scripts/fetch.sh" \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
        "$CF" && chmod +x "$CF"
fi
for _p in $(pgrep -f cloudflared 2>/dev/null); do
  [ "$_p" != "$$" ] && kill "$_p" 2>/dev/null
done
PORT=$PORT bash "$WORK/scripts/tunnel.sh" panel https 2>/dev/null || true
sleep 6
PORT=8088  bash "$WORK/scripts/tunnel.sh" web http  2>/dev/null || true

# ---------- 8. 恢复站点监控与导航页 ----------
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
