# MoltenVK Issue Draft — 提交前交产品负责人过目

> Target repo: KhronosGroup/MoltenVK
> Title: Dynamic sampler indexing into a runtime-array descriptor binding returns wrong sampler under Metal argument buffers (push-constant-driven index)

---

## Description

When a fragment shader indexes a **runtime-sized array of samplers** (`OpTypeRuntimeArray` of samplers, descriptor set 0 binding 0) with a **dynamically non-uniform index sourced from push constants**, MoltenVK (Metal argument buffer path) appears to bind/select the wrong sampler. Texture sampling through the resulting `OpSampledImage` returns zero, producing fully black output — while the same shader logic with compile-time-constant sampler indices renders correctly.

This breaks DXVK 3.x on macOS: DXVK 3.x uses a single global sampler heap (2048 samplers, one runtime array at set 0 binding 0) and passes per-draw sampler indices via push constants. Most shaders happen to resolve the index to a compile-time constant and render correctly; shaders that genuinely index the heap dynamically at runtime (e.g., UE5's tonemapper) sample garbage/zero and output black.

## SPIR-V pattern that fails

```
%178 = OpAccessChain %sampler_heap %175   ; index loaded from push constant (offset 32)
%176 = OpLoad %type_sampler %178
%181 = OpSampledImage %type_sampled_image %img %176
%182 = OpImageSampleImplicitLod ... %181
```

- `sampler_heap`: `OpTypeRuntimeArray` of `OpTypeSampler`, DescriptorSet 0, Binding 0
- Index: loaded from push constant block (offsets 32–38 carry s0–s3)
- With a constant index the same pipeline renders correctly; with the push-constant-driven index all sampled results are zero.

## Environment

- MoltenVK 1.4.2 (also reproduced with argument buffer modes 1 and 2 via `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS`)
- macOS 26.5.2 (25F84), Apple M4 (GPU family Apple 9 / Metal 4)
- Vulkan app: DXVK 3.0.2 (d3d11) under Wine 11.13; shader originates from DXBC via dxbc-spirv
- Also verified: adding `NonUniform` decoration to the index does not change the result

## Evidence

1. **HDR scene buffer fully lit** (attached `evidence-hdr-scenecolor-fully-lit.png`): the frame's
   HDR SceneColor render target, dumped one pass before tonemapping, contains a fully rendered,
   fully lit scene — geometry, lighting and post-lighting passes are all correct.
2. **Final output black**: the tonemap pass (the only shader in the frame doing dynamic
   push-constant-driven sampler-heap indexing) outputs mean luminance ≈ 0.0001.
3. **Culprit shader attached**: `fs.3f67bfcfd49b44644715da05f8a3aff9.spv` (SPIR-V) and the
   original `.dxbc`. The dynamic sampler access chain is at the instructions quoted above.
4. **Control experiment**: the identical game/frame rendered through a non-MoltenVK translation
   layer (D3DMetal) renders correctly (`evidence-d3dmetal-renders-correctly.png`), and all
   shaders with constant sampler indices render correctly through MoltenVK.

## Repro notes

- Any Vulkan app binding a runtime-array sampler heap at set 0 binding 0 and selecting the
  sampler via push constants per draw should reproduce; DXVK 3.x + any title with a
  runtime-indexed tonemapper (e.g., UE5) is a practical repro.
- We have a small HLSL→DXBC→SPIR-V harness used during diagnosis and can produce a minimal
  standalone Vulkan repro if helpful.

## Workarounds tried (all ineffective)

- `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS` mode 1 and mode 2
- Decorating the index `NonUniform`
- Replacing the runtime array with a fixed-size array (breaks aliasing/other constraints upstream)
- Exposure/tonemap-parameter changes on the app side (confirms the issue is sampler selection,
  not shader math)
