import Foundation

// CDP 截图工具：连 DevTools WebSocket，Page.captureScreenshot，存 PNG
guard CommandLine.arguments.count >= 3 else {
    print("用法: cdp-shot <ws-url> <输出.png>"); exit(1)
}
let wsURL = URL(string: CommandLine.arguments[1])!
let outPath = CommandLine.arguments[2]

let session = URLSession(configuration: .default)
let task = session.webSocketTask(with: wsURL)
task.resume()

let sem = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1

func receiveLoop() {
    task.receive { result in
        switch result {
        case .success(let message):
            if case .string(let text) = message,
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int, id == 2,
               let res = json["result"] as? [String: Any],
               let b64 = res["data"] as? String,
               let png = Data(base64Encoded: b64) {
                try? png.write(to: URL(fileURLWithPath: outPath))
                print("截图成功：\(png.count) 字节")
                exitCode = 0
                sem.signal()
                return
            }
            receiveLoop()
        case .failure(let error):
            print("WS 错误：\(error.localizedDescription)")
            sem.signal()
        }
    }
}
receiveLoop()

task.send(.string(#"{"id":1,"method":"Page.enable"}"#)) { _ in
    task.send(.string(#"{"id":2,"method":"Page.captureScreenshot","params":{"format":"png"}}"#)) { _ in }
}

_ = sem.wait(timeout: .now() + 20)
exit(exitCode)
