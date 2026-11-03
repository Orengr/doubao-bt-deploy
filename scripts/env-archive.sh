#!/bin/bash
# ============================================================
# env-archive.sh —— 把"运行环境弹药"备到持久盘（离线恢复用）
# 为什么需要它：数据在持久盘不丢，但运行环境（系统库/用户/启动脚本）
#   在沙箱重置时被清掉。本脚本把恢复所需材料提前收进持久盘 bt_env/，
#   重置后 restore.sh 优先用离线包恢复，不依赖网络、不被源拖慢。
# 用法: bash env-archive.sh    （在正常装好的环境跑一次即可，产物 ~20MB）
# 产物: $WORK/bt_env/
#   debs/    —— 关键运行库 deb（libaio1/libssl1.1/libzip4/libncurses6/libnuma1...）
#   luajit/  —— OpenResty 版 libluajit（宝塔 nginx 必需的 lua_getexdata 符号）
# ============================================================
# 持久目录自动探测：数据在哪个目录，弹药就备在哪个目录（和 restore.sh 同一套逻辑）
WORK="${DOUBAO_WORKSPACE:-$(pwd)}"
if [ ! -d "$WORK/bt_data/www" ]; then
  for cand in "$(pwd)/.." "$(pwd)/../.." "/home/user/.doubao/agent_mode/workspace"; do
    [ -d "$cand/bt_data/www" ] && WORK="$cand" && break
  done
fi
ENV="$WORK/bt_env"
mkdir -p "$ENV/debs" "$ENV/luajit"

echo "=== $(date) 开始备弹药（持久目录: $WORK） ==="

# ---------- 1. 关键运行库 deb（先 apt 下载，失败按已装版本拼镜像 URL 直拉） ----------
dl_deb(){ # $1=文件名 $2=URL
  [ -f "$ENV/debs/$1" ] && { echo "✓ $1 已存在"; return 0; }
  curl -fsSL -o "$ENV/debs/$1" "$2" && echo "✓ $1" || { echo "✗ $1 下载失败"; return 1; }
}
pkg_ver(){ dpkg -l "$1" 2>/dev/null | awk '$1=="ii"{print $3}'; }
for spec in \
  "libaio1|liba/libaio" \
  "libnuma1|n/numactl" \
  "libncurses6|n/ncurses" \
  "libzip4|libz/libzip"; do
  pkg="${spec%%|*}"; dir="${spec##*|}"
  v=$(pkg_ver "$pkg")
  if [ -n "$v" ]; then
    dl_deb "${pkg}_${v}_amd64.deb" "http://cn.archive.ubuntu.com/ubuntu/pool/main/$dir/${pkg}_${v}_amd64.deb" \
      || dl_deb "${pkg}_${v}_amd64.deb" "http://archive.ubuntu.com/ubuntu/pool/main/$dir/${pkg}_${v}_amd64.deb"
  else
    echo "跳过 $pkg（当前系统未装）"
  fi
done
# libssl1.1：Ubuntu 22.04 默认没有，必须从 focal 仓库拉
if ls "$ENV/debs"/libssl1.1*.deb >/dev/null 2>&1; then
  echo "✓ libssl1.1 deb 已备"
else
  dl_deb "libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb" \
    "http://cn.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb"
fi

# ---------- 2. OpenResty 版 libluajit（宝塔 nginx 必需，编译产物直接存） ----------
if [ -f /lib/x86_64-linux-gnu/libluajit-5.1.so.2 ] && \
   nm -D /lib/x86_64-linux-gnu/libluajit-5.1.so.2 2>/dev/null | grep -q lua_getexdata; then
  cp /lib/x86_64-linux-gnu/libluajit-5.1.so.2 "$ENV/luajit/" && echo "✓ libluajit(OpenResty版) 已备"
else
  echo "✗ 当前系统 libluajit 不含 lua_getexdata，恢复时现场编译"
fi

# ---------- 3. 汇报 ----------
echo "=============================================="
echo "离线弹药已备齐: $ENV"
echo "大小: $(du -sh "$ENV" 2>/dev/null | cut -f1)"
echo "下次重置跑 restore.sh 时，会优先用这里的东西，不再依赖网络。"
