// UE bFoundMatchingDevice 复现:同进程内 设备LUID vs 工厂枚举LUID
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
int main(void) {
    ID3D11Device *dev = NULL; D3D_FEATURE_LEVEL fl;
    if (D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
        D3D11_SDK_VERSION, &dev, &fl, NULL) != S_OK) { printf("FAIL dev\n"); return 1; }
    IDXGIDevice *xd = NULL; dev->lpVtbl->QueryInterface(dev, &IID_IDXGIDevice, (void**)&xd);
    IDXGIAdapter *da = NULL; xd->lpVtbl->GetAdapter(xd, &da);
    DXGI_ADAPTER_DESC dd; da->lpVtbl->GetDesc(da, &dd);
    printf("DEVICE  LUID=%08lx:%08lx %ls\n", dd.AdapterLuid.HighPart, dd.AdapterLuid.LowPart, dd.Description);
    IDXGIFactory *fac = NULL; CreateDXGIFactory(&IID_IDXGIFactory, (void**)&fac);
    for (UINT a = 0; ; a++) {
        IDXGIAdapter *ad = NULL;
        if (fac->lpVtbl->EnumAdapters(fac, a, &ad) != S_OK) break;
        DXGI_ADAPTER_DESC d; ad->lpVtbl->GetDesc(ad, &d);
        int match = (d.AdapterLuid.HighPart == dd.AdapterLuid.HighPart &&
                     d.AdapterLuid.LowPart == dd.AdapterLuid.LowPart);
        printf("FACTORY[%u] LUID=%08lx:%08lx match=%d\n", a,
               d.AdapterLuid.HighPart, d.AdapterLuid.LowPart, match);
        if (match) { printf("MATCH_OK\n"); return 0; }
    }
    printf("NO_MATCH——UE bFoundMatchingDevice 会在这断言\n");
    return 2;
}
