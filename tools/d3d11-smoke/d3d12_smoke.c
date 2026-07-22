/* Tea 自测工具：创建 D3D12 设备并报告适配器名（验证 D3DMetal）。
 * 编译：x86_64-w64-mingw32-gcc d3d12_smoke.c -o d3d12_smoke.exe -ld3d12 -ldxgi -ldxguid -O2
 */
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

int main(void) {
    ID3D12Device *dev = NULL;
    HRESULT hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev);
    if (FAILED(hr)) {
        printf("D3D12_FAIL hr=0x%08lx\n", (unsigned long)hr);
        return 1;
    }
    printf("D3D12_OK\n");

    IDXGIFactory4 *factory = NULL;
    if (SUCCEEDED(CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&factory))) {
        IDXGIAdapter1 *adapter = NULL;
        if (SUCCEEDED(IDXGIFactory4_EnumAdapters1(factory, 0, &adapter))) {
            DXGI_ADAPTER_DESC1 desc;
            if (SUCCEEDED(IDXGIAdapter1_GetDesc1(adapter, &desc))) {
                printf("ADAPTER=%ls VENDOR=0x%04x\n", desc.Description, desc.VendorId);
            }
            IDXGIAdapter1_Release(adapter);
        }
        IDXGIFactory4_Release(factory);
    }
    ID3D12Device_Release(dev);
    return 0;
}
