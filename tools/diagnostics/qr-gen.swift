import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else { print("用法: qr-gen <文本> <输出.png>"); exit(1) }
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(args[1].data(using: .ascii), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 16, y: 16))
let white = CIImage(color: CIColor.white).cropped(to: qr.extent.insetBy(dx: -64, dy: -64))
let final = qr.composited(over: white)
let cg = CIContext().createCGImage(final, from: final.extent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
print("生成完成")
