#!/bin/bash
# ============================================================
# fetch.sh —— 多通道下载器（解决豆包访问 GitHub 慢 / 不会用代理）
# 自动按顺序尝试：
#   1) GitHub 加速镜像（ghfast.top / gh-proxy.com，国内快）
#   2) 直连（curl 自动识别 http_proxy/https_proxy/all_proxy 环境变量，
#      如果用户/豆包配了代理，这里自动就走代理）
#   3) 用户自定义镜像前缀（环境变量 GH_MIRROR_PREFIX，可配多个）
# 支持断点续传（-C -）、失败自动切换通道，任意通道成功即返回 0。
# 用法: bash fetch.sh <完整URL> <保存路径>
# 返回: 0=成功；1=全部通道失败
# ============================================================
set -u

URL="${1:-}"
OUT="${2:-}"
if [ -z "$URL" ] || [ -z "$OUT" ]; then
  echo "用法: bash fetch.sh <URL> <保存路径>"
  exit 1
fi

# 默认 GitHub 加速镜像（可按可用性增删；环境变量 GH_MIRROR_PREFIX 可加自定义）
MIRRORS=( "https://ghfast.top" "https://gh-proxy.com" )
if [ -n "${GH_MIRROR_PREFIX:-}" ]; then
  IFS=',' read -r -a EXTRA <<< "$GH_MIRROR_PREFIX"
  MIRRORS=( "${EXTRA[@]}" "${MIRRORS[@]}" )
fi

echo "[fetch] 目标: $URL"
echo "[fetch] 保存: $OUT"

# 1) GitHub 直链走加速镜像
if echo "$URL" | grep -q '^https://github\.com/'; then
  for m in "${MIRRORS[@]}"; do
    echo "[fetch] 尝试镜像: $m"
    if curl -fSL -C - --retry 2 --connect-timeout 25 --max-time 1200 -o "$OUT" "$m/$URL" 2>/dev/null && [ -s "$OUT" ]; then
      echo "[fetch] ✅ 镜像下载成功: $m"
      exit 0
    fi
    rm -f "$OUT"
  done
fi

# 2) 直连（自动跟随 http_proxy / https_proxy / all_proxy 环境变量）
echo "[fetch] 尝试直连（若配置了代理会自动走代理）"
if curl -fSL -C - --retry 3 --connect-timeout 30 --max-time 1200 -o "$OUT" "$URL" 2>/dev/null && [ -s "$OUT" ]; then
  echo "[fetch] ✅ 直连下载成功"
  exit 0
fi
rm -f "$OUT"

echo "[fetch] ❌ 所有通道均失败。请检查网络，或设置代理后重试："
echo "       export http_proxy=http://你的代理:端口   https_proxy=http://你的代理:端口"
echo "       （或 export GH_MIRROR_PREFIX=https://另一个镜像站）"
exit 1
