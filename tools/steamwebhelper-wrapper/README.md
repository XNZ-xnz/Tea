# steamwebhelper 包装器（CEF 126 黑屏根治）

来源：[notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine)（MIT，署名保留）。

## 它解决什么

Steam 2026 客户端内置 CEF 126，在 macOS 的 wine 上有两个致命问题（**与 macOS 版本无关**，26 稳定版与 27 beta 均复现，2026-07-23 双系统实测定性）：

1. **窗口纯黑**：CEF 渲染进程跨进程创建 D3D11 交换链，撞 DXMT Issue #141 跨进程限制；GDI 与 D3D9 表面均正常，唯 CEF 内容黑。
2. **SSL 级联失败**：NetworkService 独立 utility 进程走 wine winsock 的 TLS，`handshake failed; net_error -100` 刷屏。

## 它怎么解决

把 Valve 原版 `steamwebhelper.exe` 改名为 `steamwebhelper_real.exe`，本包装器顶替原名，给每次调用前插两个 Chromium 参数后转发：

- `--disable-gpu` — CEF 走 Skia CPU 光栅化，绕开画黑的 GPU 路径（Steam 的 2D UI 够用）
- `--single-process` — renderer/utility/gpu 收编回主进程：渲染不再跨进程建交换链，NetworkService 不再独立进程走 winsock TLS。注：`--enable-features=NetworkServiceInProcess` 单用无效（CEF 126 忽略），`-cefdisablegpu` 单用也无效（实测仍黑）——两个参数缺一不可。

## 构建与安装

```bash
x86_64-w64-mingw32-gcc -municode -O2 -Wall -Wextra -static -mwindows \
    steamwebhelper-wrapper.c -o steamwebhelper.exe -lshell32
```

装进 prefix 内每个 `Steam/bin/cef/cef.win*/` 目录：先把原版改名 `steamwebhelper_real.exe`（判别法：Valve 原版几 MB，包装器 <200KB——按体积分类，防止把包装器误当原版存档），再放入包装器。

**Steam 自更新会还原原版**：更新后需重装包装器（重装逻辑按体积判别自愈，见来源仓库 `scripts/06-install-wrapper.sh`）。
