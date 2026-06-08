import Foundation
import UIKit

enum PdfWriter {
    static func writePassport(_ out: URL, title: String, rows: [PassportRow], projectDir: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 842, height: 595), format: format)
        let photos = projectDir.appendingPathComponent("photos", isDirectory: true)
        let data = renderer.pdfData { ctx in
            let perPage = 4
            let pages = max(1, Int(ceil(Double(rows.count) / Double(perPage))))
            for page in 0..<pages {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 842, height: 595))
                drawText(title, x: 24, y: 18, bold: true, size: 15)
                let headers = ["Пресет", "Прибор", "Фото", "Описание"]
                let xs: [CGFloat] = [24, 260, 330, 560]
                for (i, h) in headers.enumerated() { drawText(h, x: xs[i], y: 50, bold: true, size: 10) }
                for i in 0..<perPage {
                    let idx = page * perPage + i
                    guard idx < rows.count else { continue }
                    let row = rows[idx]
                    let y = CGFloat(72 + i * 120)
                    UIColor.lightGray.setStroke()
                    UIBezierPath(rect: CGRect(x: 24, y: y, width: 794, height: 110)).stroke()
                    drawText(row.presetLabel, x: 28, y: y + 8, size: 9, maxWidth: 220)
                    drawText(row.fixtureId, x: 264, y: y + 8, size: 9, maxWidth: 60)
                    drawText(row.description, x: 564, y: y + 8, size: 9, maxWidth: 240)
                    if let photoName = row.photoName,
                       let image = UIImage(contentsOfFile: photos.appendingPathComponent(photoName).path) {
                        image.draw(in: fit(image.size, in: CGRect(x: 334, y: y + 8, width: 210, height: 94)))
                    }
                }
            }
        }
        try data.write(to: out)
    }

    static func writePartitura(_ out: URL, title: String, rows: [PartRow], fields: [PartituraField]) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            let perPage = 28
            let pages = max(1, Int(ceil(Double(rows.count) / Double(perPage))))
            for page in 0..<pages {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 595, height: 842))
                drawText(title, x: 24, y: 18, bold: true, size: 14)
                let tableWidth: CGFloat = 547
                let colWidths = partColumnWidths(fields: fields, total: tableWidth)
                var headerX: CGFloat = 24
                for (i, field) in fields.enumerated() {
                    let colWidth = colWidths[i]
                    drawText(field.title, x: headerX + 3, y: 48, bold: true, size: 8, maxWidth: colWidth - 6)
                    headerX += colWidth
                }
                for i in 0..<perPage {
                    let idx = page * perPage + i
                    guard idx < rows.count else { continue }
                    let y = CGFloat(70 + i * 26)
                    UIColor.lightGray.setStroke()
                    UIBezierPath(rect: CGRect(x: 24, y: y, width: tableWidth, height: 24)).stroke()
                    var x: CGFloat = 24
                    for (c, field) in fields.enumerated() {
                        let colWidth = colWidths[c]
                        UIBezierPath(rect: CGRect(x: x, y: y, width: colWidth, height: 24)).stroke()
                        drawText(rows[idx].value(field.id), x: x + 3, y: y + 4, size: 7, maxWidth: colWidth - 6)
                        x += colWidth
                    }
                }
            }
        }
        try data.write(to: out)
    }

    private static func partColumnWidths(fields: [PartituraField], total: CGFloat) -> [CGFloat] {
        let weights = fields.map { partColumnWeight($0.id) }
        let sum = max(weights.reduce(0, +), 0.1)
        return weights.map { total * $0 / sum }
    }

    private static func partColumnWeight(_ id: String) -> CGFloat {
        switch id {
        case "number": return 0.75
        case "name": return 2.4
        case "trigger": return 0.9
        case "trigger_time": return 1.05
        case "fade", "downfade", "delay": return 0.65
        case "info": return 2.4
        case "command": return 1.4
        default: return 1.0
        }
    }

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, bold: Bool = false, size: CGFloat = 10, maxWidth: CGFloat = 500) {
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        NSString(string: text).draw(in: CGRect(x: x, y: y, width: maxWidth, height: 42), withAttributes: attrs)
    }

    private static func fit(_ image: CGSize, in rect: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return rect }
        let scale = min(rect.width / image.width, rect.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
