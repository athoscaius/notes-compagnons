import Foundation
import Darwin

enum ExpiryAgent {
    static func install()throws {
        guard let executable=Bundle.main.executableURL else{return}
        let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("local.compagnons.notes.expiry.plist")
        let values:[String:Any]=["Label":"local.compagnons.notes.expiry","ProgramArguments":[executable.path,"--expire"],"RunAtLoad":true,"StartInterval":900,"ProcessType":"Background"]
        let data=try PropertyListSerialization.data(fromPropertyList:values,format:.xml,options:0)
        let changed=(try? Data(contentsOf:url)) != data
        if changed{try data.write(to:url,options:.atomic)}
        func run(_ arguments:[String]) {
            let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/launchctl");p.arguments=arguments;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
            if (try? p.run()) != nil{p.waitUntilExit()}
        }
        if changed{run(["bootout","gui/\(getuid())/local.compagnons.notes.expiry"])}
        run(["bootstrap","gui/\(getuid())",url.path])
    }
}
