import AppKit
import CoreText

private struct PDFTextLine {
    let line:CTLine
    let ascent:CGFloat
    let height:CGFloat
}
final class PDFComposer {
    let context:CGContext
    let paper:Paper
    let margin:CGFloat=42.52
    var cursor:CGFloat=0
    var pageCount=0
    var width:CGFloat {paper.points.width-2*margin}
    var height:CGFloat {paper.points.height-2*margin}
    init(context:CGContext,paper:Paper){self.context=context;self.paper=paper}
    func newPage()throws {
        if pageCount>0{context.endPDFPage()}
        guard pageCount<10000 else{throw NotesError.message("La note dépasse la limite d’export PDF.")}
        context.beginPDFPage(nil);pageCount += 1;cursor=0
        context.setFillColor(NSColor.white.cgColor);context.fill(NSRect(origin:.zero,size:paper.points))
    }
    func font(size:CGFloat,bold:Bool)->CTFont {
        CTFontCreateWithName((bold ? "Arial-BoldMT":"ArialMT") as CFString,size,nil)
    }
    private func lines(_ runs:[NoteRun],size:CGFloat=11,bold:Bool=false,width:CGFloat)->[PDFTextLine] {
        let text=NSMutableAttributedString(string:"")
        for run in runs {
            text.append(NSAttributedString(string:run.text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font(size:size,bold:bold||run.bold),NSAttributedString.Key(kCTForegroundColorAttributeName as String):NSColor.black.cgColor]))
        }
        if text.length==0{text.append(NSAttributedString(string:" ",attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font(size:size,bold:bold)]))}
        let setter=CTTypesetterCreateWithAttributedString(text)
        var index=0,result:[PDFTextLine]=[]
        while index<text.length {
            let count=max(1,CTTypesetterSuggestLineBreak(setter,index,max(1,width)))
            let line=CTTypesetterCreateLine(setter,CFRange(location:index,length:min(count,text.length-index)))
            var ascent:CGFloat=0,descent:CGFloat=0,leading:CGFloat=0
            _=CTLineGetTypographicBounds(line,&ascent,&descent,&leading)
            result.append(PDFTextLine(line:line,ascent:ascent,height:max(size*1.35,ceil(ascent+descent+leading))))
            index += count
        }
        return result
    }
    private func draw(_ line:PDFTextLine,x:CGFloat,top:CGFloat){
        context.textMatrix = .identity;context.textPosition=CGPoint(x:x,y:paper.points.height-margin-top-line.ascent);CTLineDraw(line.line,context)
    }
    func paragraph(_ block:NoteBlock,next:NoteBlock?)throws {
        let level=block.kind=="paragraph" ? block.level ?? 0:0
        let sizes:[Int:CGFloat]=[1:22,2:17,3:14]
        let size=sizes[level] ?? 11,isHeading=(1...3).contains(level),bullet=block.kind=="bullet"||block.kind=="numbered"
        let markerText=block.kind=="numbered" ? "\(block.number ?? 1).":"•"
        let markerWidth:CGFloat=block.kind=="numbered" ? CGFloat(markerText.count)*7+7:12
        let indent=bullet ? CGFloat(min(5,block.level ?? 0))*12+markerWidth:0
        let content=lines(block.runs ?? [],size:size,bold:isHeading,width:width-indent)
        let before:CGFloat=isHeading&&cursor>0 ? 12:0
        if isHeading {
            let nextHeight:CGFloat
            if let next,next.kind=="table",let row=next.rows?.first {
                let cellWidth=width/CGFloat(max(1,row.count))-12
                nextHeight=(row.map{lines($0.runs,width:cellWidth).map(\.height).reduce(0,+)}.max() ?? 15)+12
            }else{nextHeight=30}
            if cursor>0 && cursor+before+content.map(\.height).reduce(0,+)+nextHeight>height{try newPage()}
        }
        cursor += cursor>0 ? before:0
        for (i,line) in content.enumerated() {
            let keepPair=(i==0 || i==content.count-2)&&i+1<content.count
            let needed=line.height+(keepPair ? content[i+1].height:0)
            if cursor>0 && cursor+needed>height{try newPage()}
            if bullet&&i==0,let marker=lines([NoteRun(text:markerText,bold:false)],width:markerWidth).first{draw(marker,x:margin+indent-markerWidth,top:cursor)}
            draw(line,x:margin+indent,top:cursor);cursor += line.height
        }
        cursor += isHeading ? 6:7
    }
    func table(_ rows:[[NoteCell]])throws {
        guard !rows.isEmpty else{return}
        let cols=max(1,rows.map(\.count).max() ?? 1),cellWidth=width/CGFloat(cols),padding:CGFloat=6
        cursor += cursor>0 ? 5:0
        for row in rows {
            let contents=(0..<cols).map{i in lines(i<row.count ? row[i].runs:[],width:cellWidth-2*padding)}
            var offsets=Array(repeating:0,count:cols)
            while zip(offsets,contents).contains(where:{$0.0<$0.1.count}) {
                let remaining=zip(offsets,contents).map{offset,lines in lines.dropFirst(offset).map(\.height).reduce(0,+)}.max() ?? 0
                let total=remaining+2*padding
                if cursor>0 && ((total<=height && cursor+total>height) || height-cursor<30){try newPage()}
                let capacity=max(1,height-cursor-2*padding)
                var chunks:[[PDFTextLine]]=[]
                for c in 0..<cols {
                    var used:CGFloat=0,chunk:[PDFTextLine]=[]
                    while offsets[c]<contents[c].count {
                        let line=contents[c][offsets[c]]
                        if !chunk.isEmpty && used+line.height>capacity{break}
                        chunk.append(line);used += line.height;offsets[c] += 1
                    }
                    chunks.append(chunk)
                }
                let rowHeight=(chunks.map{$0.map(\.height).reduce(0,+)}.max() ?? 0)+2*padding
                context.setStrokeColor(NSColor(white:0.72,alpha:1).cgColor);context.setLineWidth(0.5)
                for c in 0..<cols {
                    let x=margin+CGFloat(c)*cellWidth
                    context.stroke(NSRect(x:x,y:paper.points.height-margin-cursor-rowHeight,width:cellWidth,height:rowHeight))
                    var top=cursor+padding
                    for line in chunks[c]{draw(line,x:x+padding,top:top);top += line.height}
                }
                cursor += rowHeight
                if zip(offsets,contents).contains(where:{$0.0<$0.1.count}){try newPage()}
            }
        }
        cursor += 10
    }
    static func write(_ snapshot:NoteSnapshot,paper:Paper,to destination:URL)throws {
        try snapshot.validate()
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("NotesExport-"+UUID().uuidString+".pdf");defer{try? FileManager.default.removeItem(at:temp)}
        var box=CGRect(origin:.zero,size:paper.points)
        guard let context=CGContext(temp as CFURL,mediaBox:&box,[kCGPDFContextCreator:"Notes"] as CFDictionary) else{throw NotesError.message("La création du PDF a échoué.")}
        let composer=PDFComposer(context:context,paper:paper)
        do {
            try composer.newPage()
            for (i,block) in snapshot.blocks.enumerated() {
                if block.kind=="table"{try composer.table(block.rows ?? [])}
                else{try composer.paragraph(block,next:i+1<snapshot.blocks.count ? snapshot.blocks[i+1]:nil)}
            }
            context.endPDFPage();context.closePDF()
            try Data(contentsOf:temp).write(to:destination,options:.atomic)
        }catch{context.closePDF();throw error}
    }
}
