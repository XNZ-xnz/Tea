# tools/teabase — Tea Base(自建 CX25/26 代底座)构建资产

## 源码获取
- https://media.codeweavers.com/pub/crossover/source/crossover-sources-<v>.tar.gz
- 实测可取:25.0.1 / 25.1.0 / 26.3.0(25.0/25.1/26.x 其余 404)
- SHA256(2026-07-25 下载):
  - 25.1.0: 85458dca285ff29eed9134c0d091a84648208ac2609eeb3baa9c71acd5af106b
  - 26.3.0: ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
- cx25 = Wine 10.0 底;cx26 = Wine 11.0 底

## 构建(Rosetta x86_64,M4 Air 实测 ~25 分钟)
布局:~/Projects/tea-base-build/{cx25,cx26}(展开的源码)+ build-cx{25,26}-min(构建目录)
脚本:make-cx25.sh / make-cx26.sh(本目录;cd 到 tea-base-build 后 `arch -x86_64 ./make-cxNN.sh`)

### 踩坑清单(全部实测)
1. CC 必须显式 `clang -arch x86_64`(仅 arch -x86_64 不够,头文件 arm/i386 打架)
2. CX 树不能 --without-vulkan(win32u 无条件引用 SONAME_LIBVULKAN)
   → 借 libMoltenVK.dylib 过链检:mvk-lib/ 符号链接目录 + LDFLAGS=-L<无空格路径>
3. LDFLAGS 路径不能带空格("Application Support" 需符号链接绕开)
4. bison 用 brew 3.8(系统 2.3 太老;构建期工具 arm64 版可用)
5. cx25 需手工 stub distversion.h 进 programs/winedbg/(两个 WINDEBUG_*_MESSAGE 宏,
   CX 构建系统预生成文件;cx26 已移除该依赖)
6. 后台 make 会被工具超时杀(Killed:9 假象)→ nohup+disown 或 sentinel run --profile compile

## runtime 组装(install 后)
1. make install DESTDIR=install-cxNN → ditto bin/lib/share 到 runtimes/tea-base-cxNN
2. rpath 修复:
   - ntdll.so: install_name_tool -add_rpath "@loader_path/../../external"
   - bin/wine:  install_name_tool -add_rpath "@loader_path/../lib/external"
3. GPTK 胶水覆盖:redist/lib 的 6 对 .so/.dll + external/ 整目录 + nvngx 重命名(官方 MetalFX 步骤)
4. 符号链接(dlopen 兜底):lib/wine/x86_64-unix/ 里
   ln -sfh ../../external/D3DMetal.framework D3DMetal.framework
   ln -sf  ../../external/libd3dshared.dylib libd3dshared.dylib
5. prefix 初始化慢/挂:WINEDLLOVERRIDES 加 mscoree,mshtml=d

## 已验证事实(2026-07-25 深夜)
- cx26 + CX22胶水 = PC=0(代际不匹配,预期)
- cx26 + GPTK4胶水 = attach 过但首调 D3D11CreateDevice 跳 NULL(relay 实证 ABI 错位)
- **gptk-wine-3.0-2 + 仅换 framework 4.0b1(fw4 混合)= D3D11+D3D12 冒烟全绿,
  但 UE5 断言 bFoundMatchingDevice**(outputs/LUID 实测均一致,深层契约待查)
- cx25 编译成功(MAKE_RC=0 零错误),**组装+冒烟未做——迁移后第一件事**

## 🔑 签名发现(2026-07-26,CrossOver ground truth 破案)
CX wineloader 带正式签名 + entitlements:
- com.apple.security.cs.allow-unsigned-executable-memory
- com.apple.security.cs.disable-executable-page-protection
- com.apple.security.cs.disable-library-validation
**我们的 x86_64 产物全程无签名 → D3DMetal 胶水的运行时打表(PatchUnixCallTable)疑被
内存保护静默拦截 → 表留空 → 恒定魔数/NULL 崩溃。**ad-hoc 签名后行为立变(秒崩→长跑)。
组装流程新增步骤:所有 bin/* 与 unix .so 用 entitlements plist ad-hoc 签名
(codesign --force -s - --entitlements wine-ent.plist)。
排除清单(全实测):胶水代际×3、wow64、freetype/gnutls、CX 开关(CX_ACTIVE_GRAPHICS_BACKEND)、
loader 互换、PE 树互换、unix .so 互换——签名是最后也是真正的变量。
