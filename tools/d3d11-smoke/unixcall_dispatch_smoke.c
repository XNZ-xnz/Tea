// 派发机制诊断:拿句柄后手动 __wine_unix_call(handle, 0, NULL) 看是返回还是崩
#include <windows.h>
#include <stdio.h>
#define MemoryWineUnixFuncs 1000
typedef LONG (WINAPI *pNtQVM)(HANDLE, PVOID, ULONG, PVOID, SIZE_T, SIZE_T*);
typedef LONG (WINAPI *pUnixCall)(unsigned long long, unsigned int, void*);
int main(void) {
    HMODULE d3d11 = LoadLibraryA("d3d11.dll");
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    pNtQVM q = (pNtQVM)GetProcAddress(nt, "NtQueryVirtualMemory");
    unsigned long long handle = 0; SIZE_T ret = 0;
    q(GetCurrentProcess(), (PVOID)d3d11, MemoryWineUnixFuncs, &handle, sizeof(handle), &ret);
    pUnixCall uc = (pUnixCall)GetProcAddress(nt, "__wine_unix_call");
    printf("handle=%llx __wine_unix_call=%p\n", handle, (void*)uc);
    fflush(stdout);
    if (!uc || !handle) { printf("NO_DISPATCH_PATH\n"); return 1; }
    LONG st = uc(handle, 0, NULL);   // code 0 = init;NULL 参数可能被拒但只要「返回」就证明派发通
    printf("DISPATCH_RETURNED status=0x%08lx\n", st);
    return 0;
}
