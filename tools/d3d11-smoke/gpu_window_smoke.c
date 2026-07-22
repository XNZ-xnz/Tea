/* 8 秒 D3D9 蓝色清屏窗口：验证 GPU 表面能否呈现到 wine 窗口（macOS beta 兼容性分诊）*/
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
int main(void) {
    HWND hwnd = CreateWindowA("STATIC", "GPU-SMOKE", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              100, 100, 640, 480, NULL, NULL, NULL, NULL);
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d3d) { printf("NO_D3D9\n"); return 1; }
    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.hDeviceWindow = hwnd;
    IDirect3DDevice9 *dev = NULL;
    HRESULT hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
        D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { printf("DEV_FAIL 0x%08lx\n", (unsigned long)hr); return 1; }
    printf("D3D9_DEVICE_OK\n"); fflush(stdout);
    for (int i = 0; i < 240; i++) {
        IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0, 90, 255), 1.0f, 0);
        IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
        MSG msg; while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
        Sleep(33);
    }
    return 0;
}
