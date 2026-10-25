import AppKit
import WebKit
import PDFKit

enum EditorQA {
    static func fail(_ app:NotesApp,_ text:String){fputs("Notes QA failed: \(text)\n",stderr);app.qaCompletion=true;exit(1)}
    static func run(_ app:NotesApp){
        guard let path=app.qaOutput,let scriptURL=Bundle.main.url(forResource:"qa",withExtension:"js"),let script=try? String(contentsOf:scriptURL,encoding:.utf8) else{fail(app,"QA resources missing");return}
        app.web.evaluateJavaScript(script){result,error in
            guard error==nil,let result=result as? [String:Any],let data=result["snapshot"] as? [String:Any] else{fail(app,(error as NSError?)?.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error?.localizedDescription ?? "Invalid JavaScript result");return}
            do {
                let root=URL(fileURLWithPath:path,isDirectory:true);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("editor-checks.json"))
                let snapshot=try app.snapshot(data)
                let papers=Paper.Size.allCases.flatMap{[Paper(size:$0),Paper(size:$0,landscape:true)]}
                for paper in papers{try NoteExport.docx(snapshot,paper:paper,to:root.appendingPathComponent("note-\(paper.size.rawValue)-\(paper.landscape ? "landscape":"portrait").docx"))}
                exportPDFs(app,snapshot:snapshot,papers:papers,index:0,root:root)
            }catch{fail(app,error.localizedDescription)}
        }
    }
    static func exportPDFs(_ app:NotesApp,snapshot:NoteSnapshot,papers:[Paper],index:Int,root:URL){
        if index==papers.count {
            guard !app.records.isEmpty,let id=app.current,(try? app.store.load(id)) != nil else{fail(app,"Automatic saving did not persist the editor input");return}
            app.web.takeSnapshot(with:nil){image,error in
                if let image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:root.appendingPathComponent("notes-ui.png"))}
                print("Notes editor checks passed; first input saved locally; six Word and PDF paper formats exported.")
                app.qaCompletion=true;NSApp.terminate(nil)
            };return
        }
        let paper=papers[index],destination=root.appendingPathComponent("note-\(paper.size.rawValue)-\(paper.landscape ? "landscape":"portrait").pdf")
        let exporter=PDFExport();app.pdfExporter=exporter
        exporter.export(snapshot,paper:paper,to:destination){result in
            switch result {
            case .failure(let error):fail(app,error.localizedDescription)
            case .success:
                guard let pdf=PDFDocument(url:destination),let first=pdf.page(at:0) else{fail(app,"Invalid PDF");return}
                let rect=first.bounds(for:.mediaBox)
                guard abs(rect.width-paper.points.width)<2,abs(rect.height-paper.points.height)<2,(pdf.string ?? "").contains("Fin de la note") else{fail(app,"PDF size or content mismatch: \(rect.size), expected \(paper.points)");return}
                app.pdfExporter=nil;exportPDFs(app,snapshot:snapshot,papers:papers,index:index+1,root:root)
            }
        }
    }
}
