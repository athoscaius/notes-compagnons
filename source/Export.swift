import AppKit
import WebKit

struct Paper {
    enum Size:String,CaseIterable {case a3="A3",a4="A4",a5="A5"}
    var size:Size = .a4
    var landscape=false
    var millimetres:NSSize {
        let s:NSSize
        switch size {case .a3:s=NSSize(width:297,height:420);case .a4:s=NSSize(width:210,height:297);case .a5:s=NSSize(width:148,height:210)}
        return landscape ? NSSize(width:s.height,height:s.width):s
    }
    var points:NSSize {NSSize(width:millimetres.width*72/25.4,height:millimetres.height*72/25.4)}
    var twips:(Int,Int) {(Int((points.width*20).rounded()),Int((points.height*20).rounded()))}
}
enum NoteExport {
    static func xml(_ s:String)->String {
        s.unicodeScalars.filter{$0.value==9 || $0.value==10 || $0.value==13 || ($0.value>=32 && $0.value != 0xFFFE && $0.value != 0xFFFF)}.map(String.init).joined().replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
    }
    static func runs(_ runs:[NoteRun],heading:Int=0)->String {
        runs.map {run in
            let style=run.bold ? "<w:rPr><w:b/></w:rPr>":""
            let content=run.text.components(separatedBy:"\n").map {line in
                line.components(separatedBy:"\t").map{"<w:t xml:space=\"preserve\">\(xml($0))</w:t>"}.joined(separator:"<w:tab/>")
            }.joined(separator:"<w:br/>")
            return "<w:r>\(style)\(content)</w:r>"
        }.joined()
    }
    static func paragraph(_ block:NoteBlock)->String {
        var props=""
        if block.kind=="bullet" {props="<w:numPr><w:ilvl w:val=\"\(min(5,block.level ?? 0))\"/><w:numId w:val=\"1\"/></w:numPr>"}
        else if let level=block.level,(1...3).contains(level){props="<w:pStyle w:val=\"Heading\(level)\"/>"}
        return "<w:p><w:pPr>\(props)</w:pPr>\(runs(block.runs ?? []))</w:p>"
    }
    static func table(_ rows:[[NoteCell]],width:Int)->String {
        let columns=max(1,rows.map(\.count).max() ?? 1),cellWidth=max(120,width/columns)
        let grid=Array(repeating:"<w:gridCol w:w=\"\(cellWidth)\"/>",count:columns).joined()
        let body=rows.map {row in
            "<w:tr>"+(0..<columns).map {i in
                let content=i<row.count ? runs(row[i].runs):""
                return "<w:tc><w:tcPr><w:tcW w:w=\"\(cellWidth)\" w:type=\"dxa\"/><w:vAlign w:val=\"top\"/></w:tcPr><w:p>\(content)</w:p></w:tc>"
            }.joined()+"</w:tr>"
        }.joined()
        let edges=["top","left","bottom","right","insideH","insideV"].map{"<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"BBBBBB\"/>"}.joined()
        return "<w:tbl><w:tblPr><w:tblW w:w=\"\(width)\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders>\(edges)</w:tblBorders><w:tblCellMar><w:top w:w=\"90\" w:type=\"dxa\"/><w:left w:w=\"110\" w:type=\"dxa\"/><w:bottom w:w=\"90\" w:type=\"dxa\"/><w:right w:w=\"110\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(body)</w:tbl><w:p/>"
    }
    static func docx(_ snapshot:NoteSnapshot,paper:Paper,to destination:URL)throws {
        try snapshot.validate()
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("NotesWord-"+UUID().uuidString)
        defer{try? fm.removeItem(at:root)}
        for path in ["_rels","word/_rels"]{try fm.createDirectory(at:root.appendingPathComponent(path),withIntermediateDirectories:true)}
        func write(_ path:String,_ value:String)throws{try value.write(to:root.appendingPathComponent(path),atomically:true,encoding:.utf8)}
        let (width,height)=paper.twips,margin=850
        let body=snapshot.blocks.map{$0.kind=="table" ? table($0.rows ?? [],width:width-2*margin):paragraph($0)}.joined()
        let document="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)<w:sectPr><w:pgSz w:w=\"\(width)\" w:h=\"\(height)\"\(paper.landscape ? " w:orient=\"landscape\"":"")/><w:pgMar w:top=\"\(margin)\" w:right=\"\(margin)\" w:bottom=\"\(margin)\" w:left=\"\(margin)\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
        try write("word/document.xml",document)
        let headingStyles=[(1,44,240),(2,34,200),(3,28,160)].map {level,size,before in "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"\(before)\" w:after=\"120\"/><w:outlineLvl w:val=\"\(level-1)\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"\(size)\"/><w:color w:val=\"000000\"/></w:rPr></w:style>"}.joined()
        try write("word/styles.xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:eastAsia=\"Arial\"/><w:sz w:val=\"22\"/><w:lang w:val=\"fr-FR\"/><w:color w:val=\"000000\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"140\" w:line=\"288\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>\(headingStyles)</w:styles>")
        let levels=(0...5).map {i in "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"\(360+i*360)\"/></w:tabs><w:ind w:left=\"\(360+i*360)\" w:hanging=\"180\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\"/></w:rPr></w:lvl>"}.joined()
        try write("word/numbering.xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"multilevel\"/>\(levels)</w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>")
        try write("[Content_Types].xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/></Types>")
        try write("_rels/.rels","<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
        try write("word/_rels/document.xml.rels","<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"styles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"numbering\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/></Relationships>")
        let zip=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString+".docx");defer{try? fm.removeItem(at:zip)}
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");process.arguments=["-c","-k","--noextattr","--norsrc",root.path,zip.path]
        try process.run();process.waitUntilExit();guard process.terminationStatus==0 else{throw NotesError.message("La création du fichier Word a échoué.")}
        try Data(contentsOf:zip).write(to:destination,options:.atomic)
    }
    static func html(_ snapshot:NoteSnapshot,paper:Paper)->String {
        func rich(_ runs:[NoteRun])->String{runs.map{($0.bold ? "<strong>":"")+xml($0.text).replacingOccurrences(of:"\n",with:"<br>")+($0.bold ? "</strong>":"")}.joined()}
        var body=""
        for block in snapshot.blocks {
            if block.kind=="table" {body+="<table>"+(block.rows ?? []).map{"<tr>"+$0.map{"<td>"+rich($0.runs)+"</td>"}.joined()+"</tr>"}.joined()+"</table>"}
            else if block.kind=="bullet"{body+="<div class=\"bullet\"><span>•</span><p>"+rich(block.runs ?? [])+"</p></div>"}
            else{let tag=(1...3).contains(block.level ?? 0) ? "h\(block.level!)":"p";body+="<\(tag)>"+rich(block.runs ?? [])+"</\(tag)>"}
        }
        let css="@page{size:\(paper.millimetres.width)mm \(paper.millimetres.height)mm;margin:15mm}html,body{margin:0;padding:0;color:#000;background:#fff}body{font:11pt/1.4 Arial,sans-serif;overflow-wrap:anywhere}p{margin:0 0 7pt;white-space:pre-wrap}h1{font-size:22pt;margin:14pt 0 8pt}h2{font-size:17pt;margin:12pt 0 7pt}h3{font-size:14pt;margin:10pt 0 6pt}h1,h2,h3{break-after:avoid;color:#000}h1:first-child,h2:first-child,h3:first-child{margin-top:0}table{width:100%;table-layout:fixed;border-collapse:collapse;margin:9pt 0 12pt}td{border:.5pt solid #bbb;padding:5pt 6pt;vertical-align:top;white-space:pre-wrap}tr{break-inside:avoid}.bullet{display:flex;gap:7pt;margin-left:5pt}.bullet>p{flex:1}strong{font-weight:700}"
        return "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\(body)</body></html>"
    }
}
final class PDFExport {
    func export(_ snapshot:NoteSnapshot,paper:Paper,to destination:URL,completion:@escaping(Result<Void,Error>)->Void) {
        DispatchQueue.main.async {
            do{try PDFComposer.write(snapshot,paper:paper,to:destination);completion(.success(()))}catch{completion(.failure(error))}
        }
    }
}
