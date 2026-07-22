# recipes/

每游戏一个 `<appid>.yaml`：声明 wine 版本、图形后端、环境变量、DLL overrides、启动参数、已知问题文案。

无 recipe 的游戏走默认策略：读 exe 导入表猜 DirectX 版本选后端。

Schema 与 recipes 引擎在 P3 落地（见 PROGRESS.md），首发种子清单见原始指令第 7 节。
