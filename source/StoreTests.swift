import Foundation

enum StoreTests {
    static func run()throws {
        func check(_ value:Bool,_ message:String)throws{if !value{throw NotesError.message(message)}}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("NotesTests-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=try NoteStore(directory:root,calendar:calendar)
        func date(_ month:Int,_ day:Int,_ hour:Int=12)->Date{calendar.date(from:DateComponents(year:2026,month:month,day:day,hour:hour))!}
        let created=date(1,31),id=UUID();var note=Note(id:id,createdAt:created,updatedAt:created,html:"<p>a</p>",plain:"a")
        try store.save(note,now:created)
        try check(try store.load(id,now:created)?.plain=="a","The first letter must be stored without a title")
        note.updatedAt=date(2,20);note.plain="a modifié";note.html="<p>a modifié</p>";try store.save(note,now:date(2,20))
        try check(note.expires(calendar:calendar)==date(2,28),"One calendar month from creation, including shorter months")
        try check(try store.purge(now:date(2,28,11)).count==1,"Keep notes until the expiry time")
        try check(try store.purge(now:date(2,28)).isEmpty,"Editing must not extend retention")
        try check(!FileManager.default.fileExists(atPath:store.url(id).path),"Expired content must be removed from disk")
        try store.save(note,now:date(3,1));try check(!FileManager.default.fileExists(atPath:store.url(id).path),"An expired note cannot be resurrected by a queued edit")
        let unrelated=root.appendingPathComponent("settings.json");try Data("keep".utf8).write(to:unrelated);_=try store.purge(now:date(3,1));try check(FileManager.default.fileExists(atPath:unrelated.path),"Do not delete unrelated local files")
        let empty=NoteSnapshot(html:"<p><br></p>",plain:"",blocks:[]);try check(!empty.meaningful,"Do not create a note on startup")
        let table=NoteSnapshot(html:"<table><tr><td></td></tr></table>",plain:"",blocks:[NoteBlock(kind:"table",level:nil,runs:nil,rows:[[NoteCell(runs:[])]])]);try check(table.meaningful,"An intentionally inserted table is saved")
        for size in Paper.Size.allCases{let portrait=Paper(size:size),landscape=Paper(size:size,landscape:true);try check(portrait.points.width<portrait.points.height && landscape.points.width>landscape.points.height,"Paper orientation");try check(abs(portrait.points.width-landscape.points.height)<0.001,"Landscape must swap dimensions")}
        print("Notes checks passed: first-letter save, atomic reload, calendar-month expiry, no extension by editing, expired-edit rejection, unrelated files preserved, empty draft and paper sizes.")
    }
}
