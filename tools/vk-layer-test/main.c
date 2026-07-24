// 最小复现：VS 写 gl_Layer 的分层渲染在 MoltenVK 上是否有效
// 期望（正常）：4 层全部被染色 (255,128,64)
// 若坏：仅 layer 0 被染色，其余保持清屏色 0 —— 即幸福工厂 LUT 黑屏理论实锤
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    fprintf(stderr, "FAIL %s = %d @%d\n", #x, r_, __LINE__); exit(1); } } while (0)

static void* readAll(const char* p, size_t* n) {
    FILE* f = fopen(p, "rb"); if (!f) { perror(p); exit(1); }
    fseek(f, 0, SEEK_END); *n = ftell(f); fseek(f, 0, SEEK_SET);
    void* buf = malloc(*n); fread(buf, 1, *n, f); fclose(f); return buf;
}

int main(void) {
    const uint32_t W = 4, H = 4, LAYERS = 4;

    VkApplicationInfo ai = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    ai.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ici.pApplicationInfo = &ai;
    VkInstance inst; CK(vkCreateInstance(&ici, NULL, &inst));

    uint32_t n = 1; VkPhysicalDevice pd;
    CK(vkEnumeratePhysicalDevices(inst, &n, &pd));

    VkPhysicalDeviceVulkan12Features f12 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES };
    VkPhysicalDeviceFeatures2 f2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &f12 };
    vkGetPhysicalDeviceFeatures2(pd, &f2);
    VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd, &props);
    printf("设备: %s\n", props.deviceName);
    printf("shaderOutputLayer=%d shaderOutputViewportIndex=%d\n",
        f12.shaderOutputLayer, f12.shaderOutputViewportIndex);

    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = 0; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    VkPhysicalDeviceDynamicRenderingFeatures wantDyn = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES };
    wantDyn.dynamicRendering = VK_TRUE;
    VkPhysicalDeviceVulkan12Features want12 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, &wantDyn };
    want12.shaderOutputLayer = f12.shaderOutputLayer;
    want12.shaderOutputViewportIndex = f12.shaderOutputViewportIndex;
    const char* devExts[] = { "VK_KHR_dynamic_rendering" };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, &want12 };
    dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = devExts;
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    VkDevice dev; CK(vkCreateDevice(pd, &dci, NULL, &dev));
    VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);

    // 4x4 x 4layer 彩色附件
    VkImageCreateInfo imci = { VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
    imci.flags = VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT;   // 3D 镜像走 2D-array 视图 = DXVK 的 RTV-on-Texture3D 路径
    imci.imageType = VK_IMAGE_TYPE_3D; imci.format = VK_FORMAT_R8G8B8A8_UNORM;
    imci.extent = (VkExtent3D){ W, H, LAYERS }; imci.mipLevels = 1; imci.arrayLayers = 1;
    imci.samples = VK_SAMPLE_COUNT_1_BIT; imci.tiling = VK_IMAGE_TILING_OPTIMAL;
    imci.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VkImage img; CK(vkCreateImage(dev, &imci, NULL, &img));
    VkMemoryRequirements mr; vkGetImageMemoryRequirements(dev, img, &mr);
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    uint32_t mt = 0;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((mr.memoryTypeBits & (1u << i)) &&
            (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { mt = i; break; }
    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.allocationSize = mr.size; mai.memoryTypeIndex = mt;
    VkDeviceMemory mem; CK(vkAllocateMemory(dev, &mai, NULL, &mem));
    CK(vkBindImageMemory(dev, img, mem, 0));

    VkImageViewCreateInfo vci = { VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
    vci.image = img; vci.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY; vci.format = imci.format;
    vci.subresourceRange = (VkImageSubresourceRange){ VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, LAYERS };
    VkImageView view; CK(vkCreateImageView(dev, &vci, NULL, &view));

    VkAttachmentDescription att = { 0 };
    att.format = imci.format; att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    VkAttachmentReference ar = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkSubpassDescription sp = { 0 };
    sp.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sp.colorAttachmentCount = 1; sp.pColorAttachments = &ar;
    VkRenderPassCreateInfo rpci = { VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
    rpci.attachmentCount = 1; rpci.pAttachments = &att;
    rpci.subpassCount = 1; rpci.pSubpasses = &sp;
    VkRenderPass rp; CK(vkCreateRenderPass(dev, &rpci, NULL, &rp));

    VkFramebufferCreateInfo fbci = { VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
    fbci.renderPass = rp; fbci.attachmentCount = 1; fbci.pAttachments = &view;
    fbci.width = W; fbci.height = H; fbci.layers = LAYERS;
    VkFramebuffer fb; CK(vkCreateFramebuffer(dev, &fbci, NULL, &fb));

    size_t vn, fn2;
    void* vs = readAll("vert.spv", &vn);
    void* fs = readAll("frag.spv", &fn2);
    VkShaderModuleCreateInfo smci = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    smci.codeSize = vn; smci.pCode = vs;
    VkShaderModule vsm; CK(vkCreateShaderModule(dev, &smci, NULL, &vsm));
    smci.codeSize = fn2; smci.pCode = fs;
    VkShaderModule fsm; CK(vkCreateShaderModule(dev, &smci, NULL, &fsm));

    VkPipelineLayoutCreateInfo plci = { VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev, &plci, NULL, &pl));

    VkPipelineShaderStageCreateInfo st[2] = {
        { VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0,
          VK_SHADER_STAGE_VERTEX_BIT, vsm, "main", NULL },
        { VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0,
          VK_SHADER_STAGE_FRAGMENT_BIT, fsm, "main", NULL },
    };
    VkPipelineVertexInputStateCreateInfo vi = { VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    VkPipelineInputAssemblyStateCreateInfo ia = { VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport vp = { 0, 0, W, H, 0, 1 };
    VkRect2D sc = { { 0, 0 }, { W, H } };
    VkPipelineViewportStateCreateInfo vps = { VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO };
    vps.viewportCount = 1; vps.pViewports = &vp; vps.scissorCount = 1; vps.pScissors = &sc;
    VkPipelineRasterizationStateCreateInfo rs = { VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    rs.polygonMode = VK_POLYGON_MODE_FILL; rs.cullMode = VK_CULL_MODE_NONE; rs.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo ms = { VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState cba = { 0 };
    cba.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb = { VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO };
    cb.attachmentCount = 1; cb.pAttachments = &cba;
    VkFormat colFmt = imci.format;
    VkPipelineRenderingCreateInfo prci = { VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO };
    prci.colorAttachmentCount = 1; prci.pColorAttachmentFormats = &colFmt;
    VkGraphicsPipelineCreateInfo gp = { VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, &prci };
    gp.stageCount = 2; gp.pStages = st;
    gp.pVertexInputState = &vi; gp.pInputAssemblyState = &ia;
    gp.pViewportState = &vps; gp.pRasterizationState = &rs;
    gp.pMultisampleState = &ms; gp.pColorBlendState = &cb;
    gp.layout = pl; gp.renderPass = VK_NULL_HANDLE;   // dynamic rendering
    VkPipeline pipe; CK(vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE, 1, &gp, NULL, &pipe));

    // 读回缓冲
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.size = W * H * 4 * LAYERS; bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    VkBuffer buf; CK(vkCreateBuffer(dev, &bci, NULL, &buf));
    VkMemoryRequirements bmr; vkGetBufferMemoryRequirements(dev, buf, &bmr);
    uint32_t bmt = 0;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((bmr.memoryTypeBits & (1u << i)) &&
            (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) { bmt = i; break; }
    mai.allocationSize = bmr.size; mai.memoryTypeIndex = bmt;
    VkDeviceMemory bmem; CK(vkAllocateMemory(dev, &mai, NULL, &bmem));
    CK(vkBindBufferMemory(dev, buf, bmem, 0));

    VkCommandPoolCreateInfo cpci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    VkCommandPool cp; CK(vkCreateCommandPool(dev, &cpci, NULL, &cp));
    VkCommandBufferAllocateInfo cbai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cbai.commandPool = cp; cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbai.commandBufferCount = 1;
    VkCommandBuffer cmd; CK(vkAllocateCommandBuffers(dev, &cbai, &cmd));
    VkCommandBufferBeginInfo cbi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    CK(vkBeginCommandBuffer(cmd, &cbi));

    PFN_vkCmdBeginRenderingKHR pBegin = (PFN_vkCmdBeginRenderingKHR)vkGetDeviceProcAddr(dev, "vkCmdBeginRenderingKHR");
    PFN_vkCmdEndRenderingKHR pEnd = (PFN_vkCmdEndRenderingKHR)vkGetDeviceProcAddr(dev, "vkCmdEndRenderingKHR");
    VkImageMemoryBarrier ib = { VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER };
    ib.srcAccessMask = 0; ib.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    ib.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; ib.newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    ib.image = img; ib.subresourceRange = (VkImageSubresourceRange){ VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        0, 0, NULL, 0, NULL, 1, &ib);
    VkRenderingAttachmentInfo cai = { VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO };
    cai.imageView = view; cai.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    cai.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; cai.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    VkRenderingInfo ri = { VK_STRUCTURE_TYPE_RENDERING_INFO };
    ri.renderArea = sc; ri.layerCount = LAYERS;   // DXVK dynamic rendering 路径
    ri.colorAttachmentCount = 1; ri.pColorAttachments = &cai;
    pBegin(cmd, &ri);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipe);
    vkCmdDraw(cmd, 3, LAYERS, 0, 0);
    pEnd(cmd);
    VkImageMemoryBarrier ib2 = ib;
    ib2.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT; ib2.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    ib2.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL; ib2.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 1, &ib2);

    VkBufferImageCopy regions[4];
    for (uint32_t i = 0; i < LAYERS; i++) {
        memset(&regions[i], 0, sizeof(regions[i]));
        regions[i].bufferOffset = (VkDeviceSize)i * W * H * 4;
        regions[i].imageSubresource = (VkImageSubresourceLayers){ VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
        regions[i].imageOffset = (VkOffset3D){ 0, 0, (int32_t)i };   // 3D 镜像按 z 切片读回
        regions[i].imageExtent = (VkExtent3D){ W, H, 1 };
    }
    vkCmdCopyImageToBuffer(cmd, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, LAYERS, regions);
    CK(vkEndCommandBuffer(cmd));

    VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    CK(vkQueueSubmit(q, 1, &si, VK_NULL_HANDLE));
    CK(vkQueueWaitIdle(q));

    unsigned char* p;
    CK(vkMapMemory(dev, bmem, 0, VK_WHOLE_SIZE, 0, (void**)&p));
    int broken = 0;
    for (uint32_t i = 0; i < LAYERS; i++) {
        unsigned char* px = p + i * W * H * 4;   // 每层第一个像素
        int written = (px[0] != 0);
        printf("layer %u: RGBA=(%u,%u,%u,%u) %s\n", i, px[0], px[1], px[2], px[3],
            written ? "已写入" : "×未写入");
        if (!written) broken = 1;
    }
    printf(broken ? "结论: 分层渲染损坏(仅部分层被写入) —— LUT黑屏理论实锤\n"
                  : "结论: 分层渲染正常 —— 需另寻他因\n");
    return broken;
}
