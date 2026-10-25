import Foundation

struct Note:Codable {
    let id:UUID
    let createdAt:Date
    var updatedAt:Date
    var html:String
    var plain:String
    func expires(calendar:Calendar)->Date {calendar.date(byAdding:.month,value:1,to:createdAt) ?? createdAt.addingTimeInterval(31*86400)}
}
struct NoteRun:Codable {let text:String;let bold:Bool}
struct NoteCell:Codable {let runs:[NoteRun]}
struct NoteBlock:Codable {
    let kind:String
    let level:Int?
    let runs:[NoteRun]?
    let rows:[[NoteCell]]?
}
struct NoteSnapshot:Codable {
    let html:String
    let plain:String
    let blocks:[NoteBlock]
    func validate()throws {
        guard html.utf8.count<=20_000_000,plain.utf8.count<=20_000_000,blocks.count<=100_000,
              blocks.allSatisfy({["paragraph","bullet","table"].contains($0.kind) && (0...5).contains($0.level ?? 0)}) else{throw NotesError.message("Cette note est trop volumineuse pour être enregistrée.")}
    }
    var meaningful:Bool {!plain.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || blocks.contains{$0.kind=="table"}}
}
enum NotesError:LocalizedError {
    case message(String)
    var errorDescription:String? {if case .message(let text)=self{return text};return nil}
}
final class NoteStore {
    let directory:URL
    var calendar:Calendar
    init(directory:URL?=nil,calendar:Calendar=Calendar(identifier:.gregorian))throws {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Compagnons Notes/Notes",isDirectory:true)
        self.calendar=calendar
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:self.directory.path)
    }
    func url(_ id:UUID)->URL {directory.appendingPathComponent(id.uuidString+".json")}
    func save(_ note:Note,now:Date=Date())throws {
        if note.expires(calendar:calendar)<=now{if FileManager.default.fileExists(atPath:url(note.id).path){try FileManager.default.removeItem(at:url(note.id))};return}
        let data=try JSONEncoder().encode(note)
        try data.write(to:url(note.id),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url(note.id).path)
    }
    func load(_ id:UUID,now:Date=Date())throws->Note? {
        let path=url(id);guard FileManager.default.fileExists(atPath:path.path) else{return nil}
        let note=try JSONDecoder().decode(Note.self,from:Data(contentsOf:path))
        guard note.id==id else{throw NotesError.message("La note ne correspond pas au fichier local.")}
        if note.expires(calendar:calendar)<=now {try FileManager.default.removeItem(at:path);return nil}
        return note
    }
    @discardableResult func purge(now:Date=Date())throws->[Note] {
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isRegularFileKey],options:.skipsHiddenFiles)
        var notes:[Note]=[]
        for file in files where file.pathExtension=="json" {
            guard let id=UUID(uuidString:file.deletingPathExtension().lastPathComponent) else{continue}
            if let note=try? load(id,now:now){notes.append(note)}
        }
        return notes.sorted{$0.createdAt>$1.createdAt}
    }
}
