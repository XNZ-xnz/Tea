// wine 下跑：用 d3dcompiler_47 把 HLSL 编成 DXBC
#include <windows.h>
#include <stdio.h>
typedef HRESULT (WINAPI *pD3DCompile)(const void*, SIZE_T, const char*, const void*, void*,
    const char*, const char*, UINT, UINT, void**, void**);
typedef struct { const void* pBufferPointer; SIZE_T size; } BlobVtblStub;
int main(int argc, char** argv) {
    if (argc < 4) { printf("用法: compile <in.hlsl> <target> <out.dxbc>\n"); return 1; }
    HMODULE h = LoadLibraryA("d3dcompiler_47.dll");
    if (!h) { printf("no d3dcompiler_47\n"); return 1; }
    pD3DCompile compile = (pD3DCompile)GetProcAddress(h, "D3DCompile");
    FILE* f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char* src = malloc(n); fread(src, 1, n, f); fclose(f);
    void *blob = NULL, *err = NULL;
    HRESULT hr = compile(src, n, argv[1], NULL, NULL, "main", argv[2], 0, 0, &blob, &err);
    if (hr != 0) {
        if (err) { void** v = *(void***)err; const char* (*gp)(void*) = v[3]; printf("ERR %s\n", (char*)((void*(**)(void*))v)[3](err)); }
        printf("compile failed 0x%lx\n", (unsigned long)hr); return 1;
    }
    void** v = *(void***)blob;
    void* (WINAPI *GetBufferPointer)(void*) = (void*)v[3];
    SIZE_T (WINAPI *GetBufferSize)(void*) = (void*)v[4];
    void* p = GetBufferPointer(blob); SIZE_T sz = GetBufferSize(blob);
    FILE* o = fopen(argv[3], "wb"); fwrite(p, 1, sz, o); fclose(o);
    printf("OK %lu bytes -> %s\n", (unsigned long)sz, argv[3]);
    return 0;
}
