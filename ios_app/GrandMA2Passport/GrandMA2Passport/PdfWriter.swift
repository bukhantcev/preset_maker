import Foundation
import UIKit

enum PdfWriter {
    static func writePassport(_ out: URL, title: String, rows: [PassportRow], projectDir: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 842, height: 595), format: format)
        let photos = projectDir.appendingPathComponent("photos", isDirectory: true)
        let data = renderer.pdfData { ctx in
            let rowHeight: CGFloat = 116
            let headerTop: CGFloat = 76
            let rowTop: CGFloat = 100
            let perPage = max(1, Int((595 - rowTop - 26) / rowHeight))
            let pages = max(1, Int(ceil(Double(rows.count) / Double(perPage))))
            let presetWidth: CGFloat = 176
            let fixtureWidth: CGFloat = 62
            let photoWidth: CGFloat = 198
            let descWidth: CGFloat = 255
            let tableWidth = presetWidth + fixtureWidth + photoWidth + descWidth
            let colPreset = (842 - tableWidth) / 2
            let colFixture = colPreset + presetWidth
            let colPhoto = colFixture + fixtureWidth
            let colDesc = colPhoto + photoWidth
            for page in 0..<pages {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 842, height: 595))
                drawText(title, x: 0, y: 38, bold: true, size: 15, maxWidth: 842, center: true)
                drawCell(CGRect(x: colPreset, y: headerTop, width: presetWidth, height: 24))
                drawCell(CGRect(x: colFixture, y: headerTop, width: fixtureWidth, height: 24))
                drawCell(CGRect(x: colPhoto, y: headerTop, width: photoWidth, height: 24))
                drawCell(CGRect(x: colDesc, y: headerTop, width: descWidth, height: 24))
                drawText("Пресет", x: colPreset + 3, y: headerTop + 6, bold: true, size: 10, maxWidth: presetWidth - 6, center: true)
                drawText("Прибор", x: colFixture + 3, y: headerTop + 6, bold: true, size: 10, maxWidth: fixtureWidth - 6, center: true)
                drawText("Фото", x: colPhoto + 3, y: headerTop + 6, bold: true, size: 10, maxWidth: photoWidth - 6, center: true)
                drawText("Описание", x: colDesc + 3, y: headerTop + 6, bold: true, size: 10, maxWidth: descWidth - 6, center: true)
                for i in 0..<perPage {
                    let idx = page * perPage + i
                    guard idx < rows.count else { continue }
                    let row = rows[idx]
                    let y = rowTop + CGFloat(i) * rowHeight
                    var groupStart = idx
                    while groupStart > 0 && sameGroup(rows[groupStart], rows[groupStart - 1]) { groupStart -= 1 }
                    var groupEnd = idx
                    while groupEnd + 1 < rows.count && sameGroup(rows[groupEnd], rows[groupEnd + 1]) { groupEnd += 1 }
                    let pageStart = page * perPage
                    let pageEnd = min(rows.count - 1, pageStart + perPage - 1)
                    if idx == max(groupStart, pageStart) {
                        let spanRows = min(groupEnd, pageEnd) - idx + 1
                        let spanHeight = CGFloat(spanRows) * rowHeight
                        drawCell(CGRect(x: colPreset, y: y, width: presetWidth, height: spanHeight))
                        drawCell(CGRect(x: colFixture, y: y, width: fixtureWidth, height: spanHeight))
                        drawText(row.presetLabel, x: colPreset + 4, y: y + 8, size: 8, maxWidth: presetWidth - 8, center: true)
                        drawText(row.fixtureId, x: colFixture + 3, y: y + 8, size: 8, maxWidth: fixtureWidth - 6, center: true)
                    }
                    drawCell(CGRect(x: colPhoto, y: y, width: photoWidth, height: rowHeight))
                    drawCell(CGRect(x: colDesc, y: y, width: descWidth, height: rowHeight))
                    drawText(row.description, x: colDesc + 4, y: y + 8, size: 8, maxWidth: descWidth - 8)
                    if let photoName = row.photoName,
                       let image = UIImage(contentsOfFile: photos.appendingPathComponent(photoName).path) {
                        image.draw(in: fit(image.size, in: CGRect(x: colPhoto + 8, y: y + 4, width: 181, height: 108)))
                    }
                }
            }
        }
        try data.write(to: out)
    }

    static func writePartitura(_ out: URL, title: String, rows: [PartRow], fields: [PartituraField]) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { ctx in
            let tableX: CGFloat = 28
            let tableWidth: CGFloat = 539
            let headerTop: CGFloat = 74
            let headerHeight: CGFloat = 18
            let rowHeight: CGFloat = 15
            let rowTop = headerTop + headerHeight
            let perPage = max(1, Int((842 - rowTop - 35) / rowHeight))
            let pages = max(1, Int(ceil(Double(rows.count) / Double(perPage))))
            for page in 0..<pages {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 595, height: 842))
                drawText(title, x: 0, y: 40, bold: true, size: 14, maxWidth: 595, center: true)
                let colWidths = partColumnWidths(fields: fields, total: tableWidth)
                var headerX = tableX
                for (i, field) in fields.enumerated() {
                    let colWidth = colWidths[i]
                    drawCell(CGRect(x: headerX, y: headerTop, width: colWidth, height: headerHeight))
                    drawText(field.title, x: headerX + 3, y: headerTop + 4, bold: true, size: 6.8, maxWidth: colWidth - 6, center: true)
                    headerX += colWidth
                }
                for i in 0..<perPage {
                    let idx = page * perPage + i
                    guard idx < rows.count else { continue }
                    let y = rowTop + CGFloat(i) * rowHeight
                    var x = tableX
                    for (c, field) in fields.enumerated() {
                        let colWidth = colWidths[c]
                        drawCell(CGRect(x: x, y: y, width: colWidth, height: rowHeight))
                        let left = field.id == "name" || field.id == "info" || field.id == "command"
                        drawText(rows[idx].value(field.id), x: x + 3, y: y + 3, size: 6.4, maxWidth: colWidth - 6, center: !left)
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

    private static func drawCell(_ rect: CGRect) {
        UIColor(white: 0.45, alpha: 1).setStroke()
        UIBezierPath(rect: rect).stroke()
    }

    private static func sameGroup(_ a: PassportRow, _ b: PassportRow) -> Bool {
        a.presetLabel.trimmingCharacters(in: .whitespacesAndNewlines) == b.presetLabel.trimmingCharacters(in: .whitespacesAndNewlines) &&
        a.fixtureId.trimmingCharacters(in: .whitespacesAndNewlines) == b.fixtureId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, bold: Bool = false, size: CGFloat = 10, maxWidth: CGFloat = 500, center: Bool = false) {
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = center ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
        NSString(string: text).draw(in: CGRect(x: x, y: y, width: maxWidth, height: 80), withAttributes: attrs)
    }

    private static func fit(_ image: CGSize, in rect: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return rect }
        let scale = min(rect.width / image.width, rect.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
