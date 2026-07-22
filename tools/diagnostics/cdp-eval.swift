import Foundation
guard CommandLine.arguments.count >= 3 else { print("用法: cdp-eval <ws-url> <js表达式>"); exit(1) }
let wsURL = URL(string: CommandLine.arguments[1])!
let expr = CommandLine.arguments[2]
let task = URLSession(configuration: .default).webSocketTask(with: wsURL)
task.resume()
let sem = DispatchSemaphore(value: 0)
func loop() {
    task.receive { result in
        if case .success(.string(let text)) = result {
            if let d = text.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let id = j["id"] as? Int, id == 1 {
                if let res = j["result"] as? [String: Any],
                   let inner = res["result"] as? [String: Any] {
                    print(inner["value"] ?? inner["description"] ?? "无值")
                } else { print(text) }
                sem.signal(); return
            }
            loop()
        } else { print("WS失败"); sem.signal() }
    }
}
loop()
let payload: [String: Any] = ["id": 1, "method": "Runtime.evaluate",
    "params": ["expression": expr, "returnByValue": true]]
let data = try! JSONSerialization.data(withJSONObject: payload)
task.send(.string(String(data: data, encoding: .utf8)!)) { _ in }
_ = sem.wait(timeout: .now() + 15)
