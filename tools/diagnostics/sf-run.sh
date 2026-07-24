#!/bin/zsh
# 幸福工厂标准启动器（黑屏排查用）
# 用法: sf-run.sh [标签] [附加UE参数...]
#   例: sf-run.sh unlit -ExecCmds="viewmode unlit"
# 前置：Steam 已在跑（登录态）；DXVK 已部署在 Engine/Binaries/Win64
# 直启（带 SteamAppId）绕过 rungameid，可传任意 UE 命令行参数
set -u
TAG="${1:-run}"; shift 2>/dev/null || true
TEA="$HOME/Library/Application Support/Tea"
WINE="$TEA/runtimes/wine-devel-11.13+winemetal+mvk142/bin/wine"
G="$TEA/prefixes/steam/drive_c/Program Files (x86)/Steam/steamapps/common/Satisfactory"
L="$TEA/prefixes/steam/drive_c/users/xnz/AppData/Local/FactoryGame/Saved/Logs/FactoryGame.log"
O="${TMPDIR:-/tmp}/tea-fps-bench"; mkdir -p "$O"

# 测量纪律：防睡眠；锁屏期间截图作废（截图逻辑自查空闲时间）
pgrep -x caffeinate >/dev/null || (nohup caffeinate -dis >/dev/null 2>&1 &)

pkill -9 -f "FactoryGameSteam" 2>/dev/null
pkill -9 -f "CrashReportClient.exe|crashpad_handler" 2>/dev/null
sleep 5
[ -f "$L" ] && mv "$L" "$L.$TAG.bak"

export WINEPREFIX="$TEA/prefixes/steam" WINEDEBUG=fixme-all
export DXVK_LOG_LEVEL=info DXVK_HUD=fps,gpuload,drawcalls
export DXVK_LOG_PATH='C:\Program Files (x86)\Steam\steamapps\common\Satisfactory'
export MVK_CONFIG_RESUME_LOST_DEVICE=1
export SteamAppId=526870 SteamGameId=526870
export WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b;winedbg.exe=d"

cd "$G"
nohup "$WINE" "$G/FactoryGameSteam.exe" -NO_EOS_OVERLAY "$@" > "$O/sf-$TAG.log" 2>&1 &
echo "已直启（标签 $TAG，参数: $*）"
echo "等待引擎初始化：tail -f '$L'"
