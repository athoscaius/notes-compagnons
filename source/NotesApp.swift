import AppKit
import WebKit
import UniformTypeIdentifiers

final class ExportOptions:NSObject {
    let format=NSPopUpButton(),size=NSPopUpButton(),orientation=NSPopUpButton()
    weak var panel:NSSavePanel?
    var paper:Paper {Paper(size:Paper.Size.allCases[size.indexOfSelectedItem],landscape:orientation.indexOfSelectedItem==1)}
    var isWord:Bool {format.indexOfSelectedItem==1}
    var ext:String {isWord ? "docx":"pdf"}
    func makeView()->NSView {
        format.addItems(withTitles:["PDF","Word (.docx)"]);size.addItems(withTitles:Paper.Size.allCases.map(\.rawValue));size.selectItem(at:1);orientation.addItems(withTitles:["Portrait","Paysage"])
        format.target=self;format.action=#selector(changeFormat)
        let stack=NSStackView();stack.orientation = .horizontal;stack.spacing=16;stack.edgeInsets=NSEdgeInsets(top:10,left:0,bottom:10,right:0)
        for (title,control) in [("Format",format),("Papier",size),("Orientation",orientation)] {
            let label=NSTextField(labelWithString:title);label.font = .systemFont(ofSize:11);label.textColor = .secondaryLabelColor
            let column=NSStackView(views:[label,control]);column.orientation = .vertical;column.alignment = .leading;column.spacing=5;control.widthAnchor.constraint(equalToConstant:title=="Papier" ? 90:150).isActive=true;stack.addArrangedSubview(column)
        }
        return stack
    }
    @objc func changeFormat(){panel?.allowedContentTypes=[UTType(filenameExtension:ext) ?? .data];if let name=panel?.nameFieldStringValue {panel?.nameFieldStringValue=URL(fileURLWithPath:name).deletingPathExtension().lastPathComponent+"."+ext}}
}
final class NotesApp:NSObject,NSApplicationDelegate,WKScriptMessageHandler,WKNavigationDelegate {
    var window:NSWindow!
    var web:WKWebView!
    var store:NoteStore!
    var records:[UUID:Note]=[:]
    var current:UUID?
    var session=UUID().uuidString
    var ready=false
    var timer:Timer?
    var pdfExporter:PDFExport?
    var qaOutput:String?
    var qaCompletion:Bool=false
    var qaMode:Bool {CommandLine.arguments.contains("--qa-editor")}
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular);NSApp.appearance=NSAppearance(named:.darkAqua)
        do {
            var path:URL?
            if let i=CommandLine.arguments.firstIndex(of:"--qa-store"),i+1<CommandLine.arguments.count,CommandLine.arguments[i+1].hasPrefix("/private/tmp/"){path=URL(fileURLWithPath:CommandLine.arguments[i+1])}
            if let i=CommandLine.arguments.firstIndex(of:"--qa-output"),i+1<CommandLine.arguments.count {qaOutput=CommandLine.arguments[i+1]}
            store=try NoteStore(directory:path);records=Dictionary(uniqueKeysWithValues:try store.purge().map{($0.id,$0)})
        }catch{let alert=NSAlert();alert.messageText="Le stockage des notes est indisponible.";alert.informativeText=error.localizedDescription;alert.runModal();NSApp.terminate(nil);return}
        if !CommandLine.arguments.contains("--qa-store"){try? ExpiryAgent.install()}
        makeMenu()
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent();config.userContentController.add(self,name:"notes");config.preferences.javaScriptCanOpenWindowsAutomatically=false
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Notes";window.minSize=NSSize(width:730,height:480);window.backgroundColor=NSColor(white:0.14,alpha:1);window.isReleasedWhenClosed=false
        if let screen=NSScreen.main {window.setContentSize(NSSize(width:min(1000,screen.visibleFrame.width-60),height:min(760,screen.visibleFrame.height-80)))}
        window.contentView=web;window.center();window.setFrameAutosaveName("Compagnons.Notes.MainWindow");window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if let icon=Bundle.main.url(forResource:"AppIcon",withExtension:"png").flatMap(NSImage.init(contentsOf:)){NSApp.applicationIconImage=icon}
        guard let url=Bundle.main.url(forResource:"index",withExtension:"html") else{return}
        web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in self?.expire()}
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
    }
    func makeMenu(){
        let menu=NSMenu();func submenu(_ name:String)->NSMenu{let item=NSMenuItem();menu.addItem(item);let sub=NSMenu(title:name);item.submenu=sub;return sub}
        let app=submenu("Notes");app.addItem(withTitle:"À propos de Notes",action:#selector(about),keyEquivalent:"").target=self;app.addItem(.separator());app.addItem(withTitle:"Quitter Notes",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file=submenu("Fichier");file.addItem(withTitle:"Nouvelle note",action:#selector(newNote),keyEquivalent:"n").target=self;let export=file.addItem(withTitle:"Exporter…",action:#selector(exportFromMenu),keyEquivalent:"e");export.target=self;export.keyEquivalentModifierMask=[.command,.shift];file.addItem(withTitle:"Fermer",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let edit=submenu("Édition");edit.addItem(withTitle:"Annuler",action:Selector(("undo:")),keyEquivalent:"z");let redo=edit.addItem(withTitle:"Rétablir",action:Selector(("redo:")),keyEquivalent:"z");redo.keyEquivalentModifierMask=[.command,.shift];edit.addItem(.separator())
        for (title,action,key) in [("Couper",#selector(NSText.cut(_:)),"x"),("Copier",#selector(NSText.copy(_:)),"c"),("Coller",#selector(NSText.paste(_:)),"v"),("Tout sélectionner",#selector(NSText.selectAll(_:)),"a")]{edit.addItem(withTitle:title,action:action,keyEquivalent:key)}
        let view=submenu("Présentation");let archives=view.addItem(withTitle:"Afficher les archives",action:#selector(toggleArchives),keyEquivalent:"a");archives.target=self;archives.keyEquivalentModifierMask=[.command,.shift]
        NSApp.mainMenu=menu
    }
    @objc func about(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Notes",.applicationVersion:(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.1"),.credits:NSAttributedString(string:"Compagnons\nÉcriture simple, notes locales, exports Word et PDF.")])}
    @objc func newNote(){current=nil;session=UUID().uuidString;call("Notes.setNote(null,\(json(session)))")}
    @objc func toggleArchives(){call("document.getElementById('archive-toggle').click()")}
    @objc func exportFromMenu(){web.evaluateJavaScript("Notes.snapshot()") {[weak self] result,error in if let body=result as? [String:Any]{self?.export(body)}}}
    @objc func woke(){expire()}
    func expire(){do{let notes=try store.purge();records=Dictionary(uniqueKeysWithValues:notes.map{($0.id,$0)});if let current,records[current]==nil{self.current=nil;session=UUID().uuidString};if ready{call("Notes.archives(\(json(["notes":metadata(),"session":session])))")}}catch{showError("Les archives ne peuvent pas être lues.")}}
    func metadata()->[[String:Any]] {
        let iso=ISO8601DateFormatter()
        return records.values.sorted{$0.createdAt>$1.createdAt}.map{["id":$0.id.uuidString,"createdAt":iso.string(from:$0.createdAt),"updatedAt":iso.string(from:$0.updatedAt),"plain":String($0.plain.prefix(220)),"fallback":$0.html.contains("<table") ? "Tableau":"Note vide"]}
    }
    func json(_ object:Any)->String {
        guard let data=try? JSONSerialization.data(withJSONObject:object,options:[.fragmentsAllowed]),let value=String(data:data,encoding:.utf8) else{return "null"};return value
    }
    func call(_ script:String){web?.evaluateJavaScript(script){_,_ in}}
    func showError(_ message:String){call("Notes.error(\(json(message)))")}
    func snapshot(_ body:[String:Any])throws->NoteSnapshot {let data=try JSONSerialization.data(withJSONObject:body);let note=try JSONDecoder().decode(NoteSnapshot.self,from:data);try note.validate();return note}
    func changed(_ body:[String:Any]) {
        guard body["session"] as? String==session else{return}
        do {
            let snapshot=try snapshot(body)
            if let current,let previous=records[current],previous.expires(calendar:store.calendar)<=Date(){self.current=nil;session=UUID().uuidString;expire();call("Notes.setNote(null,\(json(session)))");return}
            if current==nil && !snapshot.meaningful{return}
            let now=Date(),old=current.flatMap{records[$0]},note=Note(id:old?.id ?? UUID(),createdAt:old?.createdAt ?? now,updatedAt:now,html:snapshot.html,plain:snapshot.plain)
            try store.save(note);records[note.id]=note;current=note.id
            call("Notes.saved(\(json(["id":note.id.uuidString,"session":session,"notes":metadata()])))")
        }catch{showError("Enregistrement impossible · exportez la note pour la conserver.")}
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame,let body=message.body as? [String:Any],let type=body["type"] as? String else{return}
        switch type {
        case "ready":ready=true;call("Notes.bootstrap(\(json(["notes":metadata(),"session":session])))");if qaMode{DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.runEditorQA()}}
        case "change":changed(body)
        case "new":newNote()
        case "open":
            if let id=(body["id"] as? String).flatMap(UUID.init(uuidString:)),let note=try? store.load(id){current=id;session=UUID().uuidString;call("Notes.setNote(\(json(["id":id.uuidString,"html":note.html,"plain":note.plain])),\(json(session)))")}
        case "paste":paste()
        case "export":export(body)
        default:break
        }
    }
    func paste(){
        let board=NSPasteboard.general;var payload:[String:String]=[:]
        if let html=board.string(forType:.html){payload["html"]=html}
        else if let data=board.data(forType:.rtf),data.count<=25_000_000,let rich=try? NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil),let html=try? rich.data(from:NSRange(location:0,length:rich.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.html,.characterEncoding:String.Encoding.utf8.rawValue]){payload["html"]=String(data:html,encoding:.utf8)}
        payload["plain"]=board.string(forType:.string) ?? board.string(forType:.URL) ?? ""
        call("Notes.acceptPaste(\(json(payload)))")
    }
    func export(_ body:[String:Any]) {
        do {
            let snapshot=try snapshot(body),panel=NSSavePanel(),options=ExportOptions();options.panel=panel
            panel.title="Exporter la note";panel.allowedContentTypes=[.pdf];panel.canCreateDirectories=true
            let date=DateFormatter();date.dateFormat="yyyy-MM-dd-HH.mm";panel.nameFieldStringValue="Note-\(date.string(from:Date())).pdf";panel.accessoryView=options.makeView()
            guard panel.runModal() == .OK,let requested=panel.url else{return}
            let destination=requested.deletingPathExtension().appendingPathExtension(options.ext)
            if destination != requested,FileManager.default.fileExists(atPath:destination.path){let alert=NSAlert();alert.messageText="Remplacer \(destination.lastPathComponent) ?";alert.addButton(withTitle:"Remplacer");alert.addButton(withTitle:"Annuler");guard alert.runModal() == .alertFirstButtonReturn else{return}}
            call("Notes.exportBusy(true)")
            if options.isWord {try NoteExport.docx(snapshot,paper:options.paper,to:destination);call("Notes.exportBusy(false);Notes.exported('Fichier Word exporté')")}
            else{let exporter=PDFExport();pdfExporter=exporter;exporter.export(snapshot,paper:options.paper,to:destination){[weak self] result in self?.pdfExporter=nil;self?.call("Notes.exportBusy(false)");switch result{case .success:self?.call("Notes.exported('PDF exporté')");case .failure:self?.showError("L’export PDF n’a pas abouti.")}}}
        }catch{call("Notes.exportBusy(false)");showError("L’export n’a pas abouti.")}
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        if let url=navigationAction.request.url,url.isFileURL,let root=Bundle.main.resourceURL,url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path+"/"){decisionHandler(.allow)}else{decisionHandler(.cancel)}
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{window.makeKeyAndOrderFront(nil);return true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if !ready || qaCompletion{return .terminateNow}
        web.evaluateJavaScript("({...Notes.snapshot(),session:\(json(session))})"){[weak self] result,_ in if let body=result as? [String:Any]{self?.changed(body)};NSApp.reply(toApplicationShouldTerminate:true)}
        return .terminateLater
    }
    func runEditorQA(){EditorQA.run(self)}
}
@main enum Main {
    static func main(){
        if CommandLine.arguments.contains("--expire"){do{_=try NoteStore().purge()}catch{exit(1)};return}
        if CommandLine.arguments.contains("--self-test"){do{try StoreTests.run();print("Notes storage and export model tests: OK")}catch{fputs("\(error.localizedDescription)\n",stderr);exit(1)};return}
        let app=NSApplication.shared,delegate=NotesApp();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}
    }
}
