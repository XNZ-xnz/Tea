# Tea 自建 DXVK for Apple M4 / MoltenVK

把 2026 最新上游 DXVK（doitsujin/dxvk main, commit 1a5919b, 报告为 DXVK 3.0.2）现代化到能在
Apple M4 + MoltenVK 1.4.2 + wine-devel 11.13 上跑起来。**这是 DXVK-macOS 现代化重建的首次成功实证**
——社区的 Gcenx/DXVK-macOS 停在 2023 的 1.10.3，本补丁让最新 DXVK 直接带起 wine。

## 为什么需要补丁

上游 DXVK 面向桌面 Vulkan 驱动，默认要求一批 M4 的 MoltenVK 尚不支持的设备特性，
以及假设查询路径永不失败。M4/MoltenVK 上这两点都不成立。

## 补丁内容

### `tea-dxvk-m4-moltenvk.patch`（主仓库 doitsujin/dxvk @ 1a5919b）

1. **4 个设备特性门改为可选**（`src/dxvk/dxvk_device_info.cpp`）：
   `geometryShader` / `shaderCullDistance` / `depthClipEnable` / `robustBufferAccess2` + `nullDescriptor`
   ——MoltenVK 1.4.2 在 M4 上不报告这些，改 required→optional 后适配器不再被 DXVK 过滤掉，
   D3D11 设备成功建到 FL 11_0。
2. **查询容错**（`src/d3d11/d3d11_query.cpp` GetData）：MoltenVK 上部分 timestamp/occlusion
   查询返回 Invalid/Failed，上游会抛致命 `DXGI_ERROR_INVALID_CALL`；改为「当作完成、数据为 0」
   继续渲染。修好后游戏越过 `PollQueryResults` 崩点。
3. **GPU 事件容错**（同文件 EVENT 查询分支，2026-07-24 晚新增）：UE 拿 D3D11_QUERY_EVENT 当
   GPU fence，MoltenVK 事件返回 Invalid 时上游抛 `DXGI_ERROR_INVALID_CALL`（UE 直接 appError 致命），
   报「未触发」则 UE 死等。改为按「已触发」放行。幸福工厂 D3D11Query.cpp:366 崩点由此过。
4. **KMT 共享句柄空指针守卫**（`src/dxvk/dxvk_memory.cpp` + `src/dxvk/dxvk_fence.cpp`，
   2026-07-24 晚新增）：上游 `initKmtHandles` 假设 Windows 驱动永远有
   `vkGetMemoryWin32HandleKHR`/`vkGetSemaphoreWin32HandleKHR`，不检查直接调用；MoltenVK 无
   `VK_KHR_external_memory_win32`，函数指针为 NULL → **跳转地址 0 崩溃**（幸福工厂 SynthBenchmark
   段 PC=0 崩溃的真凶，minidump 栈回扫 + 反汇编实锤）。加守卫后优雅失败。

### `tea-dxbc-spirv-moltenvk.patch`（子项目 subprojects/dxbc-spirv @ c5c1a5b）

5. **groupshared 不再用变量初始化器清零**（`spirv/spirv_builder.cpp` emitDclLds）：
   上游给 Workgroup 存储类变量挂 NullConstant 初始化器；Metal 的 threadgroup 内存不支持
   初始化器，MoltenVK 内置 SPIRV-Cross 生成模拟清零代码时**引用了未声明的 `gl_WorkGroupSize`**
   （MSL 编译错误），所有带 groupshared 的 compute shader 全灭。去掉初始化器（D3D11 规范本就
   不保证 groupshared 清零，上游对 scratch 也是同样理由不清零）。
6. **LocalSize 用经典字面量形式**（同文件 emitSetCsWorkgroupSize）：`LocalSizeId` 形式在
   MoltenVK 的 SPIRV-Cross 上路径较新，改回 `OpExecutionMode LocalSize` 字面量（尺寸本就是
   编译期常量，零损失，防御性修改）。

## 构建

```bash
brew install meson ninja glslang mingw-w64   # 需先 sudo xcodebuild -license accept
git clone --recursive https://github.com/doitsujin/dxvk dxvk-src && cd dxvk-src
git checkout 1a5919b && git submodule update --init
git apply /path/to/tea-dxvk-m4-moltenvk.patch
(cd subprojects/dxbc-spirv && git apply /path/to/tea-dxbc-spirv-moltenvk.patch)
meson setup --cross-file build-win64.txt --buildtype release -Denable_d3d9=false -Denable_d3d8=false build-win64
ninja -C build-win64
# 产物：build-win64/src/{d3d11,dxgi,d3d10}/*.dll
# 源码树常驻 ~/Projects/Tea/reference/dxvk-src（reference/ 已被 .gitignore 排除，重启不丢）
```

## 部署（per-game，勿放 prefix system32——会污染同 prefix 的其他游戏如 P5R）

DXVK 三件套放游戏 `Binaries/Win64/` 目录，启动加
`WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=n,b"`，底座用 `wine-devel-11.13+winemetal+mvk142`。

## 当前边界（2026-07-24 晚）

- **Against the Storm（Unity DX11）**：端到端可玩，局内 55-60 FPS 贴满帧（详见 PROGRESS）。
- **Satisfactory（UE5.3 DX11）**：补丁 3/4/5 落地后**主菜单完整渲染可交互**（Continue/New Game/
  Load 全出、compute shader 正常执行、445+ 帧零崩溃）——「UE5 世代交给底座演进」的旧结论作废，
  Tea 自己就是底座演进。已知残留：菜单 3D 背景纯黑、菜单 10 FPS（4051 draws/GPU 100%），
  以及一处 `VK_FORMAT_R16G16_UINT` 混合告警，下一轮攻。
- 旧的「无栈 null-deref」定性已破案：就是补丁 4 修的 PC=0 空函数指针调用，
  当时无栈是因为跳到地址 0 后栈帧无从回溯；用 UE 自带 minidump 的栈回扫 + PDB 反汇编定位。

排查方法论（可复用）：UE 崩溃别信日志摘要，去 `Saved/Crashes/UECC-*/` 拿
`CrashContext.runtime-xml`（分线程 PortableCallStack，认准 `IsCrashed=true` 的线程）和
`UEMinidump.dmp`（异常码/崩溃 PC/寄存器，python 手解流 4/6/9 即可）；游戏带 PDB 时
`x86_64-w64-mingw32-objdump -d` 按 ImageBase+RVA 反汇编直接见函数名。
MoltenVK 的 MSL 编译错误在 wine 进程的 stderr（跟着常驻 Steam 的 nohup 日志走）。
