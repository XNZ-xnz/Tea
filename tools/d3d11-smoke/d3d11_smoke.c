/* Tea 自测工具：创建 D3D11 设备并报告适配器名。
 * 用途：验证图形后端（DXMT / wined3d）真实可用，输出用于 CI 与诊断。
 * 编译：x86_64-w64-mingw32-gcc d3d11_smoke.c -o d3d11_smoke.exe -ld3d11 -ldxgi -ldxguid -O2
 */
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

int main(void) {
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL fl = 0;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
                                   NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (FAILED(hr)) {
        printf("D3D11_FAIL hr=0x%08lx\n", (unsigned long)hr);
        return 1;
    }
    printf("D3D11_OK feature_level=0x%04x\n", (unsigned)fl);

    IDXGIDevice *dxgiDev = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgiDev))) {
        IDXGIAdapter *adapter = NULL;
        if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgiDev, &adapter))) {
            DXGI_ADAPTER_DESC desc;
            if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc))) {
                printf("ADAPTER=%ls VENDOR=0x%04x\n", desc.Description, desc.VendorId);
            }
            IDXGIAdapter_Release(adapter);
        }
        IDXGIDevice_Release(dxgiDev);
    }
    ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(dev);
    return 0;
}
