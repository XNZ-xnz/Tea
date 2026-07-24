#!/bin/zsh
# 幸福工厂 D3DMetal 后端直启（复刻 CrossOver 的 -dx11 组合）
# 用法: sf-run-d3dmetal.sh [标签] [附加UE参数...]
# 前置：游戏目录的 DXVK 三件套已撤走（走 gptk-wine 内置 D3DMetal）
set -u
TAG="${1:-d3dm}"; shift 2>/dev/null || true
TEA="$HOME/Library/Application Support/Tea"
RT="$TEA/runtimes/gptk-wine-3.0-2"
WINE="$RT/bin/wine64"
G="$TEA/prefixes/steam/drive_c/Program Files (x86)/Steam/steamapps/common/Satisfactory"
L="$TEA/prefixes/steam/drive_c/users/xnz/AppData/Local/FactoryGame/Saved/Logs/FactoryGame.log"
O="${TMPDIR:-/tmp}/tea-fps-bench"; mkdir -p "$O"

pgrep -x caffeinate >/dev/null || (nohup caffeinate -dis >/dev/null 2>&1 &)
pkill -9 -f "FactoryGameSteam" 2>/dev/null
pkill -9 -f "CrashReportClient.exe|crashpad_handler" 2>/dev/null
sleep 5
[ -f "$L" ] && mv "$L" "$L.$TAG.bak"

export WINEPREFIX="$TEA/prefixes/steam" WINEDEBUG=fixme-all
# D3DMetal 官方环境（GPTK Read Me）
export D3DM_SUPPORT_DXR=1 ROSETTA_ADVERTISE_AVX=1 D3DM_ENABLE_METALFX=1
export SteamAppId=526870 SteamGameId=526870
export WINEDLLOVERRIDES="winedbg.exe=d"

cd "$G"
# -dx11 = 强制 DX11（复刻 CrossOver 的启动项）；D3DMetal 直接翻 DX11→Metal
nohup "$WINE" "$G/FactoryGameSteam.exe" -NO_EOS_OVERLAY -dx11 "$@" > "$O/sf-$TAG.log" 2>&1 &
echo "D3DMetal 直启（标签 $TAG，-dx11，参数: $*）"
