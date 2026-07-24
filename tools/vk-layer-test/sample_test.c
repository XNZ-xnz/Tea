// 测 MoltenVK 能否正确采样 B10G11R11_UFLOAT — BioShock/Satisfactory HDR 缓冲格式
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define CK(x) do{VkResult r=(x); if(r){fprintf(stderr,"FAIL %s=%d @%d\n",#x,r,__LINE__);exit(1);}}while(0)
static uint32_t memtype(VkPhysicalDevice pd,uint32_t bits,VkMemoryPropertyFlags f){VkPhysicalDeviceMemoryProperties p;vkGetPhysicalDeviceMemoryProperties(pd,&p);for(uint32_t i=0;i<p.memoryTypeCount;i++)if((bits&(1u<<i))&&(p.memoryTypes[i].propertyFlags&f)==f)return i;return 0;}
int main(){
  VkApplicationInfo ai={VK_STRUCTURE_TYPE_APPLICATION_INFO}; ai.apiVersion=VK_API_VERSION_1_1;
  VkInstanceCreateInfo ici={VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,0,0,&ai};
  VkInstance inst; CK(vkCreateInstance(&ici,0,&inst));
  uint32_t n=1; VkPhysicalDevice pd; vkEnumeratePhysicalDevices(inst,&n,&pd);
  // 检查 B10G11R11 的格式能力
  VkFormatProperties fp; vkGetPhysicalDeviceFormatProperties(pd,VK_FORMAT_B10G11R11_UFLOAT_PACK32,&fp);
  printf("B10G11R11 格式能力:\n");
  printf("  SAMPLED_IMAGE(可采样): %s\n", (fp.optimalTilingFeatures&VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT)?"是":"否");
  printf("  SAMPLED_IMAGE_FILTER_LINEAR(线性过滤): %s\n", (fp.optimalTilingFeatures&VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)?"是":"否");
  printf("  COLOR_ATTACHMENT(可渲染): %s\n", (fp.optimalTilingFeatures&VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT)?"是":"否");
  printf("  STORAGE_IMAGE: %s\n", (fp.optimalTilingFeatures&VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT)?"是":"否");
  // 对比 R16G16B16A16F
  VkFormatProperties fp2; vkGetPhysicalDeviceFormatProperties(pd,VK_FORMAT_R16G16B16A16_SFLOAT,&fp2);
  printf("R16G16B16A16F 对比: 可采样=%s 线性=%s 可渲染=%s\n",
    (fp2.optimalTilingFeatures&VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT)?"是":"否",
    (fp2.optimalTilingFeatures&VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)?"是":"否",
    (fp2.optimalTilingFeatures&VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT)?"是":"否");
  return 0;
}
