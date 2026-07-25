// 带窗口的 D3D11 冒烟:验证 D3DMetal 需要 winemac/窗口语境的假设
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
int main(void) {
    HWND hwnd = CreateWindowA("STATIC", "D3D11-WIN-SMOKE",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, 320, 240, NULL, NULL, NULL, NULL);
    printf("hwnd=%p\n", (void*)hwnd); fflush(stdout);
    Sleep(500);
    D3D_FEATURE_LEVEL fl;
    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
        NULL, 0, D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (hr != S_OK) { printf("FAIL hr=0x%08lx\n", hr); return 1; }
    printf("D3D11_WINDOW_OK feature_level=0x%x\n", fl); fflush(stdout);
    return 0;
}
