import UIKit
import CoreGraphics

extension FixedWidthInteger {
    var littleEndianData: Data {
        var val = self.littleEndian
        return Data(bytes: &val, count: MemoryLayout<Self>.size)
    }
}

class SubtitleImageRenderer {
    static let width = 488
    static let height = 136
    static let columns = 5
    static let blockWidth = width / columns

    func renderBMP(fixed: [Subtitle], hiragana: [Subtitle], eigo: [Subtitle]) -> Data? {
        let width = Self.width
        let height = Self.height

        // 1. Render using UIGraphics
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: rendererFormat)

        let image = renderer.image { ctx in
            let context = ctx.cgContext

            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let font = UIFont.systemFont(ofSize: 14, weight: .regular)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black,
                .paragraphStyle: paraStyle
            ]

            for i in 0..<Self.columns {
                let x = i * Self.blockWidth
                let rect = CGRect(x: x, y: 0, width: Self.blockWidth, height: height)

                let kanji = i < fixed.count ? fixed[i].text : ""
                let hira  = i < hiragana.count ? hiragana[i].text : ""
                let eng   = i < eigo.count ? eigo[i].text : ""

                let combinedText = "\(kanji)\n\(hira)\n\(eng)"
                combinedText.draw(in: rect.insetBy(dx: 4, dy: 4), withAttributes: textAttrs)
            }
        }

        guard let cgImage = image.cgImage else { return nil }

        // 2. Extract pixel buffer
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var grayBuffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(data: &grayBuffer,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 3. Convert grayscale to 1bpp — invert colors and invert Y
        let bytesPerLine = ((width + 31) / 32) * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerLine * height)

        for y in 0..<height {
            let flippedY = height - 1 - y  // invert Y
            for x in 0..<width {
                let gray = grayBuffer[y * width + x]
                let bit = gray > 127 ? 0 : 1  // invert black/white
                let byteIndex = flippedY * bytesPerLine + (x / 8)
                let bitIndex = 7 - (x % 8)
                if bit == 1 {
                    pixelData[byteIndex] |= (1 << bitIndex)
                }
            }
        }

        // 4. BMP Header
        let headerSize = 14 + 40 + 8
        let pixelDataSize = pixelData.count
        let fileSize = headerSize + pixelDataSize

        var bmp = Data()

        // File Header (14 bytes)
        bmp.append("BM".data(using: .ascii)!)
        bmp.append(UInt32(fileSize).littleEndianData)
        bmp.append(UInt32(0).littleEndianData)
        bmp.append(UInt32(headerSize).littleEndianData)

        // DIB Header (40 bytes)
        bmp.append(UInt32(40).littleEndianData)
        bmp.append(Int32(width).littleEndianData)
        bmp.append(Int32(height).littleEndianData)   // keep height positive = bottom-up
        bmp.append(UInt16(1).littleEndianData)
        bmp.append(UInt16(1).littleEndianData)
        bmp.append(UInt32(0).littleEndianData)
        bmp.append(UInt32(pixelDataSize).littleEndianData)
        bmp.append(UInt32(2835).littleEndianData)
        bmp.append(UInt32(2835).littleEndianData)
        bmp.append(UInt32(2).littleEndianData)
        bmp.append(UInt32(0).littleEndianData)

        // Color Palette: 0 = black, 1 = white
        bmp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])     // black
        bmp.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x00])     // white

        bmp.append(contentsOf: pixelData)

        return bmp
    }


}
