#!/bin/zsh
# 把 steamcmd（test prefix）下载的游戏搬进 Steam 客户端（steam prefix）的库
# 用法: ./relocate-steamcmd-game.sh <appid>
set -e
APPID="${1:?用法: relocate-steamcmd-game.sh <appid>}"
TEA="$HOME/Library/Application Support/Tea"
SRC="$TEA/prefixes/test/drive_c/steamcmd/steamapps"
DST="$TEA/prefixes/steam/drive_c/Program Files (x86)/Steam/steamapps"
ACF="$SRC/appmanifest_${APPID}.acf"
[ -f "$ACF" ] || { echo "❌ 找不到 $ACF（下载没完成？）"; exit 1; }
INSTALLDIR=$(grep '"installdir"' "$ACF" | sed 's/.*"installdir"[^"]*"\([^"]*\)".*/\1/')
echo "游戏目录: $INSTALLDIR"
mkdir -p "$DST/common"
mv "$SRC/common/$INSTALLDIR" "$DST/common/"     # 同卷 rename，秒级
cp "$ACF" "$DST/"
echo "✅ 已搬运：$DST/common/$INSTALLDIR + appmanifest_${APPID}.acf"
echo "重启 Steam 后客户端即认领此游戏"
