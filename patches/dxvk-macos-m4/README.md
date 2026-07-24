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
7. **原子 Store 改发 OpAtomicExchange 丢弃结果**（同文件 emitAtomic，2026-07-24 深夜新增）：
   SPIRV-Cross 翻译纹理/纹素缓冲原子操作时统一在 MSL 调用后补 `.x` 分量提取——对有返回值的
   原子合法，对返回 void 的 `atomic_store` 生成 `atomic_store(...).x`（MSL 编译错误）。
   Exchange 丢结果与 Store 语义等价。**此补丁 + 下面第 8 条落地后幸福工厂 DEVICE_LOST 清零**。

### 主仓库补丁（续）

8. **整数格式附件强制关混合**（`src/dxvk/dxvk_graphics.cpp`，2026-07-24 深夜新增）：
   D3D11 语义下驱动忽略整数格式上的混合，DXVK 原样传给 Vulkan（违反 Vulkan 规范），
   MoltenVK 告警 `Blending is enabled for attachment VK_FORMAT_R16G16_UINT`。
   按 D3D11 语义强制 `blendEnable=false`。（注：修完告警消失，但未解决光照黑屏——见下）

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
- **Satisfactory（UE5.3 DX11）**：全部 8 项补丁落地后——主菜单可交互、**存档世界可加载**、
  **DEVICE_LOST 清零、RenderThread 挂死清零**、compute shader 全部编译执行。
  **剩一个大问题：光照全灭（黑屏）**。决定性证据：固定曝光（Engine.ini
  `r.EyeAdaptationQuality=0`，已写入用户配置待还原）后菜单场景能看到**橙色自发光火花粒子**，
  其余全黑——几何/粒子在渲染，但所有光源贡献为零，只剩 emissive。嫌疑排查状态：
  ①整数格式混合已修（无效）②聚簇光照的光源网格 compute（dispatch 在跑但产出可能为零）
  ③GS 阴影管线失败（Metal 无 GS，`Fragment input(s) user(locn2) mismatching`——阴影不该全黑）
  ④下一步候选：对比 AoTS（前向渲染正常）与 UE 延迟渲染差异；试 `-forwardshading`；
  用 UE ShowFlag/console 变量二分光照链路；查 light grid 的 R32G32B32A32 纹理采样路径。
- 旧的「无栈 null-deref」定性已破案：就是补丁 4 修的 PC=0 空函数指针调用，
  当时无栈是因为跳到地址 0 后栈帧无从回溯；用 UE 自带 minidump 的栈回扫 + PDB 反汇编定位。

排查方法论（可复用）：UE 崩溃别信日志摘要，去 `Saved/Crashes/UECC-*/` 拿
`CrashContext.runtime-xml`（分线程 PortableCallStack，认准 `IsCrashed=true` 的线程）和
`UEMinidump.dmp`（异常码/崩溃 PC/寄存器，python 手解流 4/6/9 即可）；游戏带 PDB 时
`x86_64-w64-mingw32-objdump -d` 按 ImageBase+RVA 反汇编直接见函数名。
MoltenVK 的 MSL 编译错误在 wine 进程的 stderr（跟着常驻 Steam 的 nohup 日志走）。

## 光照黑屏排查台账（2026-07-24 深夜，进行中）

| 弹药 | 结果 |
|---|---|
| `r.ForwardShading=1` | ❌ 早期 init 挂死，已还原 |
| `r.ShadowQuality=0`（全关阴影） | 仍黑，但 FPS 6.8→13.6 / render pass 127→65（阴影链确实被剥离）——**排除「全被阴影盖黑」** |
| `r.DefaultFeature.AutoExposure.Bias=8`（+8EV=256 倍增亮） | 仍纯黑——**排除曝光压黑**（若有任何非零亮度必然过曝） |
| `r.TiledDeferredShading=0` + `r.LightFunctionQuality=0` | 仍黑——排除 tiled/clustered 光源剔除 |
| `r.GBufferFormat=0`（8 位法线编码） | 仍黑——排除法线编码精度路径 |
| `r.SceneColorFormat=2`（RGBA8 场景色） | 仍黑——排除浮点格式加法混合失效 |
| 游戏内控制台（` 键注入） | 没弹出（疑被 UMG 吞键），type.swift 工具已入库待续 |

**关阴影后 GS 管线失败清零**（实证 GS 三连败=点光源阴影 cubemap，与黑屏正交）。

### 下一会话的武器清单（按威力排序）
1. **Metal GPU 帧捕获**：`METAL_CAPTURE_ENABLED=1` + `MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=2` +
   `MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE=xxx.gputrace` → Xcode 打开逐 pass 看每个渲染目标内容，
   直接看到哪一步把光照归零——不再猜。
2. 游戏内控制台打通（先点击游戏区拿键盘焦点再按 `；或查 Input.ini 绑定），打通后
   `viewmode unlit` / `vis` 系列即时二分。
3. 升级 MoltenVK 到最新（SPIRV-Cross 修复可能已上游）；或换 MoltenVK debug 构建拿逐管线日志。
4. UE 侧偶发 RHIThread 崩溃（FD3D11DynamicRHI::RHIEnd*）待独立排查。

发现极暗轮廓 → 新主假说：场景在渲染但被曝光/色调映射链压到近黑。
另发现 UE 侧偶发 RHIThread 崩溃（FD3D11DynamicRHI::RHIEnd*，频率约 1/3 启动），与黑屏正交，待查。

### 光照黑屏·收敛理论（2026-07-24 深夜末，证据链最强）

**主嫌：色调映射 LUT 的 3D 纹理分层渲染损坏**（MoltenVK 的 VS 写 gl_Layer 路径疑似无效）。
UE 把 32³ 调色 LUT 用 32 层分层渲染写入 Volume 纹理；若只有第 0 层（最暗输入段）被正确写入：
- 暗输入映射正常 → 「黑的还是黑」不露馅
- 亮输入采到未初始化层 → 归零 → **场景全灭**
- Coffee Stain logo 实测只剩约 5% 亮度（过 LUT）、UMG UI 满亮（不过 LUT）——完美吻合
- 自发光火花 = HDR 极亮值采样边缘层的残值

**已完整排除**（全部实验记录在案）：阴影、曝光（+8EV 在手动挡无效为无效实验，后以
UsePreExposure=0 + Basic 自动挡补测仍黑）、PreExposure、整数混合、tiled 剔除、GBuffer 格式、
场景色格式、GS 管线（关阴影后清零）、MVK fast-math。

**验证/修复路径**：
1. 最小 Vulkan 复现：VS 写 gl_Layer 渲到 3D/数组附件，读回验证各层 —— 定 MoltenVK 责任
2. MoltenVK HEAD brew 构建失败；改从 GitHub release/自编 MoltenVK 换版本对照
3. 若实锤：修 MoltenVK（Metal 支持 VS render_target_array_index，大概率是 MoltenVK 管线胶水 bug）
   或 DXVK 侧把 3D RTV 分层绘制改写为逐层多 pass（重）
4. 平行路径：游戏内控制台（`被吞）打通后 `r.LUT.Size` 等现场试

补充：`r.PostProcessing.PreferCompute=1` → 画面变为**彻底全黑（连 DXVK HUD 都不可见）**，
与像素路径（UI/HUD 可见）行为明显不同——后处理实现层被进一步锁定为问题域。
（compute 后处理让最终输出全黑 = compute 写出/拷贝路径另有一坏；先还原此 cvar。）

### 更正与新测量纪律（2026-07-24 21:00）

- ⚠️ **撤回**：「PreferCompute=1 → 连 HUD 都黑」结论无效——实测发现该时段 Mac 已锁屏/息屏，
  截到的是锁屏黑画面。PreferCompute 与 r.SkyAtmosphere=0 两轮实验结果均未知，需重测。
- **新测量纪律**：无人值守跑视觉实验前必须 ①挂 `caffeinate -dis` 防睡眠 ②截屏前用
  `Quartz CGSessionCopyCurrentDictionary` 查 `CGSSessionScreenIsLocked`，锁屏期间的一切截图作废。
- ✅ **重要阴性结果（结论可靠，独立于锁屏）**：`tools/vk-layer-test/` 最小 Vulkan 复现证明
  MoltenVK 1.4.2 的 VS gl_Layer 分层渲染**完全正常**——2D 数组与「3D 镜像 2D-array 兼容视图」
  （即 DXVK 的 RTV-on-Texture3D 路径）双双 4/4 层正确写入。**LUT 分层渲染损坏理论出局**。
  shaderOutputLayer=1 已确认上报。

### 下一轮待执行（已备好，等屏幕解锁）
- Engine.ini 已还原基线并только加 `ShowFlag.Lighting=0`（强制无光照=直出 albedo）：
  场景显形→实锤光照 pass（继续 ShowFlag.DirectLighting/GlobalIllumination/DeferredLighting 二分）；
  仍黑→base pass/GBuffer 上游。
- 新工具 `tools/diagnostics/sf-run.sh`：直启带任意 UE 参数（-ExecCmds 可免控制台执行命令），
  自动挂 caffeinate 防锁屏污染。

### 无屏复现流水线（tools/vk-layer-test/，全阴性=底层栈无罪）

HLSL→(wine d3dcompiler_47)→DXBC→(dxbc-spirv 原生 dxbc_compiler)→SPIR-V→MoltenVK 渲染读回。
实测矩阵（MoltenVK 1.4.2 / M4，全部 4/4 层正确写入）：
| 变体 | 结果 |
|---|---|
| GLSL gl_Layer + 2D 数组 + 传统 render pass | ✅ |
| GLSL gl_Layer + 3D 镜像 2D-array 兼容视图（DXVK RTV-on-Texture3D 路径） | ✅ |
| DXVK dxbc-spirv 生成的 SV_RenderTargetArrayIndex SPIR-V + 3D 视图 | ✅ |
| 同上 + dynamic rendering（DXVK 3.x 实际路径） | ✅ |

结论：社区 nastys/MoltenVK「CombineLUTs 只写第 0 层」bug（2022 era）在 MoltenVK 1.4.2
已不存在于任何我能构造的等价路径——幸福工厂黑屏另有机制，等 ShowFlag.ColorGrading=0
在真游戏里的裁决（已在菜单待命）。偶发崩溃错误码勘正：887A0007=DXGI DEVICE_RESET。
