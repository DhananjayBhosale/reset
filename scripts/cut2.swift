import Foundation
import Vision
import CoreImage
import AppKit

// usage: cut2 <sheet.png> <outdir> <prefix>
// Each subject Vision finds is assigned to one of five columns by its centre, so a character never
// picks up a neighbour's limb. The mask is eroded a touch and feathered so no black fringe survives.
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2]), prefix = args[3]
let moods = ["fresh", "focused", "tired", "asleep", "waking"]
let ci = CIImage(contentsOf: url)!
let W = Int(ci.extent.width), H = Int(ci.extent.height)
let handler = VNImageRequestHandler(ciImage: ci)
let req = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([req])
guard let obs = req.results?.first else { print("no subject"); exit(1) }
let ctx = CIContext()
let gray = CGColorSpaceCreateDeviceGray()

func maskBytes(_ set: IndexSet) -> [UInt8] {
    let buf = try! obs.generateScaledMaskForImage(forInstances: set, from: handler)
    let img = CIImage(cvPixelBuffer: buf)
    var out = [UInt8](repeating: 0, count: W * H)
    ctx.render(img, toBitmap: &out, rowBytes: W, bounds: CGRect(x: 0, y: 0, width: W, height: H), format: .L8, colorSpace: gray)
    return out
}

// Column of each instance, by the centre of its mask. Only the biggest subject per column is kept,
// which drops ghost copies and stray bits of background the model added.
var best = [(inst: Int, size: Int)?](repeating: nil, count: 5)
for inst in obs.allInstances {
    let m = maskBytes(IndexSet(integer: inst))
    var sx = 0, n = 0
    for i in 0..<(W * H) where m[i] > 127 { sx += i % W; n += 1 }
    guard n > 400 else { continue }
    let c = min(4, (sx / n) * 5 / W)
    if best[c] == nil || n > best[c]!.size { best[c] = (inst, n) }
}
let columns = best.map { $0.map { IndexSet(integer: $0.inst) } ?? IndexSet() }

// Source pixels, top-left origin rows.
let src = ctx.createCGImage(ci, from: ci.extent)!
var rgba = [UInt8](repeating: 0, count: W * H * 4)
let bctx = CGContext(data: &rgba, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bctx.draw(src, in: CGRect(x: 0, y: 0, width: W, height: H))

for (ci2, set) in columns.enumerated() {
    guard !set.isEmpty else { print("empty column", ci2); continue }
    // Mask from Vision (CIImage origin is bottom-left; render(toBitmap:) writes top row first).
    let maskImg = CIImage(cvPixelBuffer: try obs.generateScaledMaskForImage(forInstances: set, from: handler))
    let shaped = maskImg
        .applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": 1.5])   // eat the dark rim
        .applyingGaussianBlur(sigma: 0.9)                                          // soft, anti-aliased edge
        .cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
    var m = [UInt8](repeating: 0, count: W * H)
    ctx.render(shaped, toBitmap: &m, rowBytes: W, bounds: CGRect(x: 0, y: 0, width: W, height: H), format: .L8, colorSpace: gray)
    var minX = W, maxX = 0, minY = H, maxY = 0
    var out = [UInt8](repeating: 0, count: W * H * 4)
    for y in 0..<H { for x in 0..<W {
        let a = m[y * W + x]; guard a > 0 else { continue }
        let i = (y * W + x) * 4
        out[i] = rgba[i]; out[i + 1] = rgba[i + 1]; out[i + 2] = rgba[i + 2]; out[i + 3] = a
        if a > 20 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    } }
    // Square, bottom-aligned, 512 px.
    let pad = 8
    let cw = maxX - minX + 1 + 2 * pad, ch = maxY - minY + 1 + 2 * pad, side = max(cw, ch)
    var sq = [UInt8](repeating: 0, count: side * side * 4)
    let ox = (side - cw) / 2 + pad, oy = side - ch + pad
    for y in minY...maxY { for x in minX...maxX {
        let s = (y * W + x) * 4, d = ((y - minY + oy) * side + (x - minX + ox)) * 4
        sq[d] = out[s]; sq[d + 1] = out[s + 1]; sq[d + 2] = out[s + 2]; sq[d + 3] = out[s + 3]
    } }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    memcpy(rep.bitmapData!, sq, sq.count)
    let big = NSImage(size: NSSize(width: side, height: side)); big.addRepresentation(rep)
    let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
    NSGraphicsContext.current?.imageInterpolation = .high
    big.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
    NSGraphicsContext.restoreGraphicsState()
    let name = "\(prefix)-\(moods[ci2]).png"
    try small.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print(name, set.count, "instances")
}
