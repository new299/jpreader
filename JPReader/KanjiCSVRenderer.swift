import UIKit

struct Entry {
    let kanji: String
    let word: String
    let hiragana: String
    let meaning: String
}

class KanjiCSVRenderer {
    var entries: [Entry] = []
    
    init(csvString: String) {
        let lines = csvString.components(separatedBy: .newlines)
        for line in lines {
            let fields = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if fields.count >= 4 {
                entries.append(Entry(kanji: String(fields[0]),
                                     word: String(fields[1]),
                                     hiragana: String(fields[2]),
                                     meaning: String(fields[3])))
            }
        }
    }
    
    func generate1bppBMP(for index: Int, printanswer: Bool = true) -> Data? {

        guard index >= 0, index < entries.count else { return nil }
        let entry = entries[index]
        
        let width = 488
        let height = 136
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        // Create grayscale context
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        
        // White background
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        UIGraphicsPushContext(context)
        
        // Draw text
        let kanjiFont = UIFont(name: "Hiragino Mincho ProN", size: 100) ?? UIFont.systemFont(ofSize: 100)
        let wordFont = UIFont(name: "Hiragino Sans", size: 24) ?? UIFont.systemFont(ofSize: 24)
        
        let kanjiAttr: [NSAttributedString.Key: Any] = [.font: kanjiFont, .foregroundColor: UIColor.black]
        let textAttr: [NSAttributedString.Key: Any] = [.font: wordFont, .foregroundColor: UIColor.black]
        
        entry.kanji.draw(in: CGRect(x: 0, y: 0, width: 136, height: 136), withAttributes: kanjiAttr)
        entry.word.draw(in: CGRect(x: 150, y: 20, width: 320, height: 30), withAttributes: textAttr)
        if(printanswer) {
            entry.hiragana.draw(in: CGRect(x: 150, y: 60, width: 320, height: 30), withAttributes: textAttr)
            entry.meaning.draw(in: CGRect(x: 150, y: 100, width: 320, height: 30), withAttributes: textAttr)
        }
        UIGraphicsPopContext()
        
        guard let grayData = context.data else { return nil }
        let grayBuffer = grayData.bindMemory(to: UInt8.self, capacity: width * height)
        
        // BMP rows must be padded to 4-byte boundaries
        let rowBytes = ((width + 31) / 32) * 4
        var pixelData = Data(count: rowBytes * height)
        
        // Fill pixelData with proper bits (0 = black, 1 = white), top to bottom
        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = y * rowBytes + (x / 8)
                let bitIndex = 7 - (x % 8)
                let gray = grayBuffer[y * width + x]
                if gray < 128 {
                    pixelData[byteIndex] &= ~(1 << bitIndex) // black
                } else {
                    pixelData[byteIndex] |= (1 << bitIndex)  // white
                }
            }
        }
        
        // BMP headers
        let fileSize = 14 + 40 + 8 + pixelData.count
        let pixelOffset = 14 + 40 + 8
        
        var bmp = Data()
        bmp.append(contentsOf: [0x42, 0x4D]) // BM
        bmp.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        bmp.append(contentsOf: [0, 0, 0, 0]) // reserved
        bmp.append(contentsOf: withUnsafeBytes(of: UInt32(pixelOffset).littleEndian) { Data($0) })
        
        // BITMAPINFOHEADER
        bmp.append(contentsOf: withUnsafeBytes(of: UInt32(40).littleEndian) { Data($0) })
        bmp.append(contentsOf: withUnsafeBytes(of: Int32(width).littleEndian) { Data($0) })
        bmp.append(contentsOf: withUnsafeBytes(of: Int32(height).littleEndian) { Data($0) })
        bmp.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // planes
        bmp.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // bpp
        bmp.append(contentsOf: [0,0,0,0]) // no compression
        bmp.append(contentsOf: withUnsafeBytes(of: UInt32(pixelData.count).littleEndian) { Data($0) })
        bmp.append(contentsOf: [0x13,0x0B,0,0]) // horiz res
        bmp.append(contentsOf: [0x13,0x0B,0,0]) // vert res
        bmp.append(contentsOf: [0,0,0,0]) // colors used
        bmp.append(contentsOf: [0,0,0,0]) // important colors
        
        // Palette: black and white
        bmp.append(contentsOf: [0x00,0x00,0x00,0x00]) // black
        bmp.append(contentsOf: [0xFF,0xFF,0xFF,0x00]) // white
        
        bmp.append(pixelData)
        return bmp
    }
}
