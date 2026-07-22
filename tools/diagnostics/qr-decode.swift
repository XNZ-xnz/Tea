import Foundation
import Vision
import CoreImage

guard CommandLine.arguments.count >= 2,
      let img = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    print("读图失败"); exit(1)
}
let request = VNDetectBarcodesRequest()
let handler = VNImageRequestHandler(ciImage: img)
try? handler.perform([request])
let results = request.results ?? []
if results.isEmpty { print("❌ 未识别出任何条码——这图对机器也不可读") }
for r in results {
    print("类型: \(r.symbology.rawValue)")
    print("内容: \(r.payloadStringValue ?? "（无文本载荷）")")
}
