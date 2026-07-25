// DXGI 适配器/输出枚举冒烟:验证 UE bFoundMatchingDevice 的前提
#include <windows.h>
#include <dxgi.h>
#include <stdio.h>
int main(void) {
    IDXGIFactory *fac = NULL;
    HRESULT hr = CreateDXGIFactory(&IID_IDXGIFactory, (void**)&fac);
    if (hr != S_OK) { printf("FAIL factory 0x%08lx\n", hr); return 1; }
    for (UINT a = 0; ; a++) {
        IDXGIAdapter *ad = NULL;
        if (fac->lpVtbl->EnumAdapters(fac, a, &ad) != S_OK) break;
        DXGI_ADAPTER_DESC d; ad->lpVtbl->GetDesc(ad, &d);
        printf("ADAPTER[%u] %ls LUID=%08lx:%08lx\n", a, d.Description,
               d.AdapterLuid.HighPart, d.AdapterLuid.LowPart);
        for (UINT o = 0; ; o++) {
            IDXGIOutput *out = NULL;
            if (ad->lpVtbl->EnumOutputs(ad, o, &out) != S_OK) break;
            DXGI_OUTPUT_DESC od; out->lpVtbl->GetDesc(out, &od);
            printf("  OUTPUT[%u] %ls attached=%d monitor=%p\n", o,
                   od.DeviceName, od.AttachedToDesktop, (void*)od.Monitor);
        }
    }
    printf("ENUM_DONE\n");
    return 0;
}
