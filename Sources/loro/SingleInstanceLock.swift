import Darwin
import Foundation

/// Protects CLI and app launches from competing for the hotkey and microphone.
/// Never unlink the file: other processes may already have opened its inode.
final class SingleInstanceLock {
    private let descriptor: Int32
    let acquired: Bool

    init() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Loro", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("instance.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        let acquired = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        if !acquired, errno != EWOULDBLOCK {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw error
        }
        self.descriptor = descriptor
        self.acquired = acquired
    }

    deinit { close(descriptor) }
}
