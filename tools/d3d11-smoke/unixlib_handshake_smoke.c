// unixlib 握手诊断:PE 侧拿 d3d11.dll 的 MemoryWineUnixFuncs 句柄
#include <windows.h>
#include <stdio.h>
#define MemoryWineUnixFuncs 1000
typedef LONG (WINAPI *pNtQueryVirtualMemory)(HANDLE, PVOID, ULONG, PVOID, SIZE_T, SIZE_T*);
int main(void) {
    HMODULE d3d11 = LoadLibraryA("d3d11.dll");
    printf("d3d11 module=%p\n", (void*)d3d11);
    if (!d3d11) return 1;
    pNtQueryVirtualMemory q = (pNtQueryVirtualMemory)GetProcAddress(
        GetModuleHandleA("ntdll.dll"), "NtQueryVirtualMemory");
    unsigned long long handle = 0; SIZE_T ret = 0;
    LONG st = q(GetCurrentProcess(), (PVOID)d3d11, MemoryWineUnixFuncs,
                &handle, sizeof(handle), &ret);
    printf("NtQueryVirtualMemory(MemoryWineUnixFuncs) status=0x%08lx handle=%llx\n",
           st, handle);
    printf(st == 0 && handle ? "HANDSHAKE_OK\n" : "HANDSHAKE_FAIL\n");
    return 0;
}
