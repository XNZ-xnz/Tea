// 把多张截图的左上角 HUD 区域裁出来纵向拼成一张，便于一次读完多次采样
// 用法: hudstrip.swift <out.png> <in1.png> <in2.png> ...
//
// 为什么需要它：帧率在同场景同 draw call 下浮动极大，单次读数不可靠，
// 必须多采样取中位。拼成一张图可一次读完，省去逐张查看。
import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 3 else {
    print("用法: hudstrip.swift <out.png> <in1.png> <in2.png> ...")
    exit(1)
}
let outPath = CommandLine.arguments[1]
let inputs = Array(CommandLine.arguments.dropFirst(2))
let cropW = 760, cropH = 300

var crops: [CGImage] = []
for p in inputs {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let rect = CGRect(x: 0, y: 0, width: min(cropW, img.width), height: min(cropH, img.height))
    if let c = img.cropping(to: rect) { crops.append(c) }
}
guard !crops.isEmpty else { print("无有效输入"); exit(1) }

let W = crops.map(\.width).max()!
let H = crops.reduce(0) { $0 + $1.height }
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
var y = H
for c in crops {
    y -= c.height
    ctx.draw(c, in: CGRect(x: 0, y: y, width: c.width, height: c.height))
}
guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
print("已拼接 \(crops.count) 张 → \(outPath)")
