#!/bin/bash
# ============================================================
# php-offline.sh —— PHP 8.1 一键安装（预编译包秒装优先）
# 方式 A（秒装 ~1 分钟）：bt_res/php81-prebuilt.tar.xz
#   = 用 PHP 官方源码编译的标准产物（官方原包、默认配置，
#     不含任何个人信息），解压即用。
# 方式 B（兜底 ~20-40 分钟）：bt_res/php-8.1.31.tar.gz
#   = PHP 官方源码包（php.net / 宝塔 CDN 原包），自动并行编译。
# 两种方式装好后目录结构都是宝塔标准 /www/server/php/81，面板直接识别。
# 用法: bash php-offline.sh
# 日志: /tmp/php_install.log
# ============================================================
exec > /tmp/php_install.log 2>&1
set -e
echo "=== $(date) PHP 8.1 安装开始 ==="

VER="8.1.31"
PREFIX="/www/server/php/81"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- 0. 已有则跳过 ----------
if [ -x "$PREFIX/sbin/php-fpm" ]; then
    echo "PHP 已存在: $PREFIX/sbin/php-fpm，跳过"
    exit 0
fi

# ---------- 1. 方式 A：预编译包秒装（bt_res/ 优先） ----------
PREBUILT=""
for cand in "$SCRIPT_DIR/bt_res/php81-prebuilt.tar.xz" "$SCRIPT_DIR/../bt_res/php81-prebuilt.tar.xz" "$WORK/bt_res/php81-prebuilt.tar.xz" "/tmp/php81-prebuilt.tar.xz"; do
  [ -f "$cand" ] && PREBUILT="$cand" && break
done
if [ -n "$PREBUILT" ]; then
    echo "找到预编译包: $PREBUILT（官方源码编译的标准产物，解压即用）"
    cd /
    sudo tar -xf "$PREBUILT"
    if [ -d /www/server/php/81pkg ] && [ ! -d "$PREFIX" ]; then
        sudo mv /www/server/php/81pkg "$PREFIX"
    fi
    sudo mkdir -p "$PREFIX/var/run"
    sudo chown -R www:www "$PREFIX/var" 2>/dev/null || sudo useradd -s /sbin/nologin www 2>/dev/null || true
    # init 脚本 + 启动
    if [ ! -f /etc/init.d/php-fpm-81 ]; then
        cat > /tmp/php-fpm-81 <<'INIT'
#!/bin/bash
prefix=/www/server/php/81
php_fpm_BIN=${prefix}/sbin/php-fpm
php_fpm_CONF=${prefix}/etc/php-fpm.conf
php_fpm_PID=${prefix}/var/run/php-fpm.pid
php_fpm_OPTS="--fpm-config $php_fpm_CONF --pid $php_fpm_PID"
case "$1" in
  start)
    echo "Starting php-fpm-81 ..."
    mkdir -p ${prefix}/var/run
    chown -R www:www ${prefix}/var 2>/dev/null
    $php_fpm_BIN $php_fpm_OPTS
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
        sudo cp /tmp/php-fpm-81 /etc/init.d/php-fpm-81
        sudo chmod +x /etc/init.d/php-fpm-81
    fi
    sudo /etc/init.d/php-fpm-81 start
    sleep 1
    if pgrep -f "php-fpm.*php/81" >/dev/null 2>&1 || [ -S /tmp/php-cgi-81.sock ]; then
        echo "PHP 8.1 预编译包安装成功（秒装）"
    else
        echo "启动未确认，检查日志: $PREFIX/var/log/php-fpm.log"
    fi
    echo "=== PHP 安装完成（方式 A 预编译） ==="
    exit 0
fi

# ---------- 1. 找离线源码包（bt_res/ 优先，其次在线下载） ----------
SRC=""
for cand in "$SCRIPT_DIR/bt_res/php-${VER}.tar.gz" "$SCRIPT_DIR/../bt_res/php-${VER}.tar.gz" "/tmp/php-${VER}.tar.gz"; do
  [ -f "$cand" ] && SRC="$cand" && break
done
cd /tmp
if [ -n "$SRC" ]; then
    echo "找到离线源码包: $SRC（官方原包，干净）"
    cp -f "$SRC" .
else
    echo "无离线包，在线下载官方源码（php.net 原包）..."
    curl -fSL -o php-${VER}.tar.gz "https://download.bt.cn/src/php-${VER}.tar.gz" || \
    curl -fSL -o php-${VER}.tar.gz "https://www.php.net/distributions/php-${VER}.tar.gz"
fi

# ---------- 2. 编译依赖 ----------
sudo apt-get install -y build-essential pkg-config libxml2-dev libsqlite3-dev \
    libcurl4-openssl-dev libpng-dev libonig-dev libzip-dev libssl-dev \
    libbz2-dev libreadline-dev libsqlite3-dev 2>/dev/null || true

# ---------- 3. 解压 + configure（宝塔标准参数） ----------
rm -rf php-${VER}
tar -xf php-${VER}.tar.gz
cd php-${VER}
sudo mkdir -p "$PREFIX"
sudo useradd -s /sbin/nologin www 2>/dev/null || true
./configure --prefix="$PREFIX" --with-fpm-user=www --with-fpm-group=www \
    --enable-fpm --with-mysqli --with-pdo-mysql --with-zlib --enable-mbstring \
    --enable-gd --with-openssl --enable-sockets --enable-pcntl --with-curl \
    --with-iconv --enable-fileinfo --enable-bcmath --enable-exif --enable-ftp \
    --with-zip --enable-intl 2>&1 | tail -3

# ---------- 4. 并行编译安装 ----------
make -j$(nproc) 2>&1 | tail -3
sudo make install 2>&1 | tail -3

# ---------- 5. 配置 php.ini + php-fpm.conf + init 脚本 ----------
sudo cp php.ini-production "$PREFIX/etc/php.ini"
sudo sed -i 's/^memory_limit.*/memory_limit = 256M/' "$PREFIX/etc/php.ini"
sudo sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/' "$PREFIX/etc/php.ini"
sudo sed -i 's/^post_max_size.*/post_max_size = 64M/' "$PREFIX/etc/php.ini"
sudo cp "$PREFIX/etc/php-fpm.conf.default" "$PREFIX/etc/php-fpm.conf"
sudo sed -i 's/^;pid = run\/php-fpm.pid/pid = run\/php-fpm.pid/' "$PREFIX/etc/php-fpm.conf"
sudo cp "$PREFIX/etc/php-fpm.d/www.conf.default" "$PREFIX/etc/php-fpm.d/www.conf" 2>/dev/null || true

# init 脚本（宝塔兼容：面板/系统用 /etc/init.d/php-fpm-81 启停）
sudo tee /etc/init.d/php-fpm-81 >/dev/null <<'INIT'
#!/bin/bash
# php-fpm-81 init script（宝塔兼容路径）
prefix=/www/server/php/81
php_fpm_BIN=${prefix}/sbin/php-fpm
php_fpm_CONF=${prefix}/etc/php-fpm.conf
php_fpm_PID=${prefix}/var/run/php-fpm.pid
php_fpm_OPTS="--fpm-config $php_fpm_CONF --pid $php_fpm_PID"
php_fpm_user=www

case "$1" in
  start)
    echo "Starting php-fpm-81 ..."
    mkdir -p ${prefix}/var/run
    chown -R www:www ${prefix}/var 2>/dev/null
    $php_fpm_BIN $php_fpm_OPTS
    ;;
  stop)
    echo "Stopping php-fpm-81 ..."
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
sudo mkdir -p "$PREFIX/var/run"
sudo chown -R www:www "$PREFIX/var" 2>/dev/null

# ---------- 6. 启动 ----------
sudo /etc/init.d/php-fpm-81 start
sleep 1
if pgrep -f "php-fpm.*php/81" >/dev/null 2>&1 || [ -S /tmp/php-cgi-81.sock ]; then
    echo "PHP 8.1 启动成功"
else
    echo "启动未确认，检查日志: /www/server/php/81/var/log/php-fpm.log"
fi
echo "=== PHP 安装完成 ==="
