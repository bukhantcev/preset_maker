import Foundation
import UIKit

enum Xlsx {
    static func writePassport(_ out: URL, title: String, rows: [PassportRow], projectDir: URL) throws {
        DebugLog.write("Xlsx writePassport start out=\(out.path)")
        let tmp = out.deletingPathExtension().appendingPathExtension("tmp")
        let package = tmp.appendingPathExtension("dir")
        try? FileManager.default.removeItem(at: package)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        DebugLog.write("Xlsx writePassport package created")
        try put(package, "[Content_Types].xml", contentTypes(images: true))
        DebugLog.write("Xlsx writePassport content types")
        try put(package, "_rels/.rels", rels())
        try put(package, "xl/workbook.xml", workbook("Паспорт"))
        try put(package, "xl/_rels/workbook.xml.rels", workbookRels())
        try put(package, "xl/styles.xml", styles())
        DebugLog.write("Xlsx writePassport base xml")
        try put(package, "xl/worksheets/sheet1.xml", passportSheet(title: title, rows: rows))
        DebugLog.write("Xlsx writePassport sheet")
        try put(package, "xl/worksheets/_rels/sheet1.xml.rels", sheetRels(rows: rows))
        try put(package, "xl/drawings/drawing1.xml", drawing(rows: rows))
        try put(package, "xl/drawings/_rels/drawing1.xml.rels", drawingRels(rows: rows))
        DebugLog.write("Xlsx writePassport drawings")
        let photos = projectDir.appendingPathComponent("photos", isDirectory: true)
        var img = 1
        for row in rows {
            guard let photoName = row.photoName else { continue }
            let photo = photos.appendingPathComponent(photoName)
            if let data = try? Data(contentsOf: photo) {
                try put(package, "xl/media/image\(img).jpg", data)
                img += 1
            }
        }
        DebugLog.write("Xlsx writePassport media count=\(img - 1)")
        try zipDirectory(package, to: out)
        DebugLog.write("Xlsx writePassport zip done")
        try? FileManager.default.removeItem(at: package)
        DebugLog.write("Xlsx writePassport done")
    }

    static func writePartitura(_ out: URL, title: String, rows: [PartRow], fields: [PartituraField]) throws {
        let tmp = out.deletingPathExtension().appendingPathExtension("tmp")
        let package = tmp.appendingPathExtension("dir")
        try? FileManager.default.removeItem(at: package)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try put(package, "[Content_Types].xml", contentTypes(images: false))
        try put(package, "_rels/.rels", rels())
        try put(package, "xl/workbook.xml", workbook("Партитура"))
        try put(package, "xl/_rels/workbook.xml.rels", workbookRels())
        try put(package, "xl/styles.xml", styles())
        try put(package, "xl/worksheets/sheet1.xml", partSheet(title: title, rows: rows, fields: fields))
        try zipDirectory(package, to: out)
        try? FileManager.default.removeItem(at: package)
    }

    static func readPassportRows(_ xlsx: URL) throws -> [PassportRow] {
        let entries = try unzipStoredEntries(xlsx)
        guard let sheet = entries["xl/worksheets/sheet1.xml"],
              let xml = String(data: sheet, encoding: .utf8) else { return [] }
        let shared: [String]
        if let data = entries["xl/sharedStrings.xml"], let ss = String(data: data, encoding: .utf8) {
            shared = ss.components(separatedBy: "<si").dropFirst().map { collectText($0).xmlUnescaped }
        } else {
            shared = []
        }
        var result: [PassportRow] = []
        var lastPreset = ""
        var lastFixture = ""
        for chunk in xml.components(separatedBy: "<row ").dropFirst() {
            guard let rowNo = Int(attr(chunk, "r")), rowNo >= 3 else { continue }
            var cells: [String: String] = [:]
            for cellChunk in chunk.components(separatedBy: "<c ").dropFirst() {
                let ref = attr(cellChunk, "r")
                if ref.isEmpty { continue }
                cells[columnLetters(ref)] = cellValue(cellChunk, shared: shared)
            }
            var preset = cells["A"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var fixture = cells["B"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = cells["D"] ?? ""
            if preset.isEmpty { preset = lastPreset }
            if fixture.isEmpty { fixture = lastFixture }
            if preset.isEmpty && fixture.isEmpty && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            lastPreset = preset
            lastFixture = fixture
            result.append(PassportRow(presetLabel: preset, fixtureId: fixture, presetNo: "", photoName: nil, description: description))
        }
        return result
    }

    private static func put(_ root: URL, _ path: String, _ text: String) throws {
        try put(root, path, Data(text.utf8))
    }

    private static func put(_ root: URL, _ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func zipDirectory(_ dir: URL, to out: URL) throws {
        DebugLog.write("Xlsx zipDirectory start")
        try? FileManager.default.removeItem(at: out)
        var files: [(String, Data)] = []
        let basePath = dir.resolvingSymlinksInPath().path
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where !url.hasDirectoryPath {
                let path = url.resolvingSymlinksInPath().path
                let rel = path.hasPrefix(basePath + "/") ? String(path.dropFirst(basePath.count + 1)) : url.lastPathComponent
                files.append((rel, try Data(contentsOf: url)))
            }
        }
        DebugLog.write("Xlsx zipDirectory files=\(files.count)")
        var archive = Data()
        var central = Data()
        for (index, item) in files.enumerated() {
            let path = item.0
            let data = item.1
            DebugLog.write("Xlsx zipDirectory file \(index) \(path) bytes=\(data.count)")
            let offset = UInt32(archive.count)
            let name = Data(path.utf8)
            let crc = crc32(data)
            archive.appendU32(0x04034b50)
            archive.appendU16(20)
            archive.appendU16(0)
            archive.appendU16(0)
            archive.appendU16(0)
            archive.appendU16(0)
            archive.appendU32(crc)
            archive.appendU32(UInt32(data.count))
            archive.appendU32(UInt32(data.count))
            archive.appendU16(UInt16(name.count))
            archive.appendU16(0)
            archive.append(name)
            archive.append(data)

            central.appendU32(0x02014b50)
            central.appendU16(20)
            central.appendU16(20)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(crc)
            central.appendU32(UInt32(data.count))
            central.appendU32(UInt32(data.count))
            central.appendU16(UInt16(name.count))
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(0)
            central.appendU32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(archive.count)
        DebugLog.write("Xlsx zipDirectory central bytes=\(central.count) archive=\(archive.count)")
        archive.append(central)
        archive.appendU32(0x06054b50)
        archive.appendU16(0)
        archive.appendU16(0)
        archive.appendU16(UInt16(files.count))
        archive.appendU16(UInt16(files.count))
        archive.appendU32(UInt32(central.count))
        archive.appendU32(centralOffset)
        archive.appendU16(0)
        try archive.write(to: out)
        DebugLog.write("Xlsx zipDirectory wrote")
    }

    private static func passportSheet(title: String, rows: [PassportRow]) -> String {
        var xml = sheetOpen() + "<sheetData>"
        xml += row(1, cell("A1", title, 1))
        xml += row(2, cell("A2", "Пресет", 2) + cell("B2", "Прибор", 2) + cell("C2", "Фото", 2) + cell("D2", "Описание", 2))
        for (i, r) in rows.enumerated() {
            let rowNo = i + 3
            xml += row(rowNo,
                       cell("A\(rowNo)", r.presetLabel, 3) +
                       cell("B\(rowNo)", r.fixtureId, 3) +
                       cell("C\(rowNo)", "", 3) +
                       cell("D\(rowNo)", r.description, 4),
                       height: 96)
        }
        xml += "</sheetData><mergeCells count=\"1\"><mergeCell ref=\"A1:D1\"/></mergeCells>"
        xml += "<drawing r:id=\"rId1\"/></worksheet>"
        return xml
    }

    private static func partSheet(title: String, rows: [PartRow], fields: [PartituraField]) -> String {
        var xml = sheetOpen(cols: partColumns(fields)) + "<sheetData>"
        let lastCol = colName(fields.count)
        xml += row(1, cell("A1", title, 1))
        var header = ""
        for (i, field) in fields.enumerated() {
            header += cell("\(colName(i + 1))2", field.title, 2)
        }
        xml += row(2, header)
        for (r, part) in rows.enumerated() {
            var cells = ""
            let rowNo = r + 3
            for (c, field) in fields.enumerated() {
                let style = field.id == "name" || field.id == "info" ? 4 : 3
                cells += cell("\(colName(c + 1))\(rowNo)", part.value(field.id), style)
            }
            xml += row(rowNo, cells)
        }
        xml += "</sheetData><mergeCells count=\"1\"><mergeCell ref=\"A1:\(lastCol)1\"/></mergeCells></worksheet>"
        return xml
    }

    private static func sheetOpen(cols: String = "<cols><col min=\"1\" max=\"1\" width=\"42\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"14\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"42\" customWidth=\"1\"/><col min=\"4\" max=\"20\" width=\"28\" customWidth=\"1\"/></cols>") -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>\(cols)"
    }

    private static func partColumns(_ fields: [PartituraField]) -> String {
        var xml = "<cols>"
        for (i, field) in fields.enumerated() {
            let col = i + 1
            xml += "<col min=\"\(col)\" max=\"\(col)\" width=\"\(partColumnWidth(field.id))\" customWidth=\"1\"/>"
        }
        return xml + "</cols>"
    }

    private static func partColumnWidth(_ id: String) -> String {
        switch id {
        case "number": return "12"
        case "name": return "46"
        case "trigger": return "13"
        case "trigger_time": return "15"
        case "fade", "downfade", "delay": return "10"
        case "info": return "50"
        case "command": return "30"
        default: return "18"
        }
    }

    private static func row(_ n: Int, _ cells: String, height: Int? = nil) -> String {
        if let height { return "<row r=\"\(n)\" ht=\"\(height)\" customHeight=\"1\">\(cells)</row>" }
        return "<row r=\"\(n)\">\(cells)</row>"
    }

    private static func cell(_ ref: String, _ text: String, _ style: Int) -> String {
        "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t>\(esc(text))</t></is></c>"
    }

    private static func colName(_ index: Int) -> String {
        var n = index
        var s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(65 + n % 26)!) + s
            n /= 26
        }
        return s
    }

    private static func contentTypes(images: Bool) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        if images { xml += "<Override PartName=\"/xl/drawings/drawing1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>" }
        return xml + "</Types>"
    }

    private static func rels() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
    }

    private static func workbook(_ sheet: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\(esc(sheet))\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    }

    private static func workbookRels() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    }

    private static func sheetRels(rows: [PassportRow]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing\" Target=\"../drawings/drawing1.xml\"/></Relationships>"
    }

    private static func drawing(rows: [PassportRow]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        var img = 1
        for (i, row) in rows.enumerated() where row.photoName != nil {
            let r = i + 2
            xml += "<xdr:twoCellAnchor><xdr:from><xdr:col>2</xdr:col><xdr:colOff>120000</xdr:colOff><xdr:row>\(r)</xdr:row><xdr:rowOff>90000</xdr:rowOff></xdr:from><xdr:to><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(r + 1)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(img)\" name=\"image\(img)\"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed=\"rId\(img)\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>"
            img += 1
        }
        return xml + "</xdr:wsDr>"
    }

    private static func drawingRels(rows: [PassportRow]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        var img = 1
        for row in rows where row.photoName != nil {
            xml += "<Relationship Id=\"rId\(img)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(img).jpg\"/>"
            img += 1
        }
        return xml + "</Relationships>"
    }

    private static func styles() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Arial\"/></font><font><b/><sz val=\"12\"/><name val=\"Arial\"/></font></fonts><fills count=\"1\"><fill><patternFill patternType=\"none\"/></fill></fills><borders count=\"2\"><border/><border><left style=\"thin\"/><right style=\"thin\"/><top style=\"thin\"/><bottom style=\"thin\"/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"5\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"><alignment horizontal=\"center\"/></xf><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyFont=\"1\" applyBorder=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyBorder=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyBorder=\"1\"><alignment horizontal=\"left\" vertical=\"center\" wrapText=\"1\"/></xf></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"
    }

    private static func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unzipStoredEntries(_ url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        var pos = 0
        var result: [String: Data] = [:]
        while pos + 30 < data.count {
            guard data.u32(pos) == 0x04034b50 else { break }
            let method = data.u16(pos + 8)
            let compressedSize = Int(data.u32(pos + 18))
            let nameLen = Int(data.u16(pos + 26))
            let extraLen = Int(data.u16(pos + 28))
            let nameStart = pos + 30
            let nameEnd = nameStart + nameLen
            let dataStart = nameEnd + extraLen
            let dataEnd = dataStart + compressedSize
            guard nameEnd <= data.count, dataEnd <= data.count else { break }
            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            if method == 0 {
                result[name] = Data(data[dataStart..<dataEnd])
            }
            pos = dataEnd
        }
        return result
    }

    private static func attr(_ xml: String, _ name: String) -> String {
        let key = "\(name)=\""
        guard let range = xml.range(of: key) else { return "" }
        let rest = xml[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }

    private static func columnLetters(_ ref: String) -> String {
        String(ref.prefix { $0 >= "A" && $0 <= "Z" })
    }

    private static func cellValue(_ cell: String, shared: [String]) -> String {
        let type = attr(cell, "t")
        if type == "inlineStr" { return collectText(cell).xmlUnescaped }
        if let start = cell.range(of: "<v>"), let end = cell.range(of: "</v>") {
            let raw = String(cell[start.upperBound..<end.lowerBound])
            if type == "s", let i = Int(raw), shared.indices.contains(i) {
                return shared[i]
            }
            return raw.xmlUnescaped
        }
        return ""
    }

    private static func collectText(_ xml: String) -> String {
        var result = ""
        var search = xml[...]
        while let tStart = search.range(of: "<t") {
            guard let close = search[tStart.upperBound...].firstIndex(of: ">"),
                  let end = search[close...].range(of: "</t>") else { break }
            result += String(search[search.index(after: close)..<end.lowerBound])
            search = search[end.upperBound...]
        }
        return result
    }
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
        var c = (crc ^ UInt32(byte)) & 0xff
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
        }
        crc = (crc >> 8) ^ c
    }
    return crc ^ 0xffffffff
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

private extension String {
    var xmlUnescaped: String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
