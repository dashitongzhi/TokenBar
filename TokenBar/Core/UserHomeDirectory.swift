import Darwin
import Foundation

enum UserHomeDirectory {
    static var url: URL {
        if let passwd = getpwuid(getuid()),
           let directory = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
