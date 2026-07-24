# Tea 自建 DXVK for Apple M4 / MoltenVK

把 2026 最新上游 DXVK（doitsujin/dxvk main, commit 1a5919b, 报告为 DXVK 3.0.2）现代化到能在
Apple M4 + MoltenVK 1.4.2 + wine-devel 11.13 上跑起来。**这是 DXVK-macOS 现代化重建的首次成功实证**
——社区的 Gcenx/DXVK-macOS 停在 2023 的 1.10.3，本补丁让最新 DXVK 直接带起 wine。

## 为什么需要补丁

上游 DXVK 面向桌面 Vulkan 驱动，默认要求一批 M4 的 MoltenVK 尚不支持的设备特性，
以及假设查询路径永不失败。M4/MoltenVK 上这两点都不成立。

## 补丁内容（`tea-dxvk-m4-moltenvk.patch`）

1. **4 个设备特性门改为可选**（`src/dxvk/dxvk_device_info.cpp`）：
   `geometryShader` / `shaderCullDistance` / `depthClipEnable` / `robustBufferAccess2` + `nullDescriptor`
   ——MoltenVK 1.4.2 在 M4 上不报告这些，改 required→optional 后适配器不再被 DXVK 过滤掉，
   D3D11 设备成功建到 FL 11_0。
2. **查询容错**（`src/d3d11/d3d11_query.cpp` GetData）：MoltenVK 上部分 timestamp/occlusion
   查询返回 Invalid/Failed，上游会抛致命 `DXGI_ERROR_INVALID_CALL`；改为「当作完成、数据为 0」
   继续渲染。修好后游戏越过 `PollQueryResults` 崩点。

## 构建

```bash
brew install meson ninja glslang mingw-w64   # 需先 sudo xcodebuild -license accept
git clone --recursive https://github.com/doitsujin/dxvk dxvk-src && cd dxvk-src
git apply /path/to/tea-dxvk-m4-moltenvk.patch
meson setup --cross-file build-win64.txt --buildtype release -Denable_d3d9=false -Denable_d3d8=false build-win64
ninja -C build-win64
# 产物：build-win64/src/{d3d11,dxgi,d3d10}/*.dll
```

## 部署（per-game，勿放 prefix system32——会污染同 prefix 的其他游戏如 P5R）

DXVK 三件套放游戏 `Binaries/Win64/` 目录，启动加
`WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b"`，底座用 `wine-devel-11.13+winemetal+mvk142`。

## 当前边界（2026-07-24）

Satisfactory（UE5.3）实测：设备✓ 交换链✓ 查询崩点✓修复 → 深入 RHI 运行时后遇
**无调用栈的空指针访问（读 0x0）**，需调试器级排查，待续。日志深度较各前序方案（DXMT 43K、
DXVK-macOS 1.10.3 停 139K 死锁）已是最深，且死因从"无可用 D3D11 转译器"变为"自建 DXVK 可用、
剩游戏特定运行时崩"——性质已根本改变。此补丁对其他 DX11 游戏通用，是 Tea 的核心可复用资产。
