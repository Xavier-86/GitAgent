//
//  LocalTerminalSession.swift
//  GitAgent
//
//  macOS login shell backed by a native pseudo-terminal.
//

#if os(macOS)
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class LocalTerminalSession {
    private(set) var state: TerminalSessionState = .disconnected
    var onOutput: ((Data) -> Void)?

    private var masterHandle: FileHandle?
    private var processSource: DispatchSourceProcess?
    private var processID: pid_t?
    private var scopedDirectoryURL: URL?

    func connect(directory: String? = nil, bookmarkData: Data? = nil) {
        guard state == .disconnected || isFailed else { return }
        state = .connecting

        do {
            try beginSecurityScope(bookmarkData)

            var masterFD: Int32 = -1
            var windowSize = winsize(
                ws_row: 24,
                ws_col: 80,
                ws_xpixel: 0,
                ws_ypixel: 0
            )

            let shell = preferredShell()
            // Login shell the way Terminal.app does it: argv[0] is the shell
            // name with a leading '-'.
            let arguments = ["-" + (shell as NSString).lastPathComponent]
            let argumentPointers: [UnsafeMutablePointer<CChar>?] =
                arguments.map { strdup($0) } + [nil]
            var environment = ProcessInfo.processInfo.environment
            // GUI apps launched by launchd inherit a minimal environment
            // (SHELL may even point at /bin/bash regardless of the user's
            // actual shell). Rebuild the login environment from the user
            // database so the shell behaves like a Terminal.app session.
            if let passwd = getpwuid(getuid()) {
                environment["HOME"] = String(cString: passwd.pointee.pw_dir)
                environment["USER"] = String(cString: passwd.pointee.pw_name)
                environment["LOGNAME"] = String(cString: passwd.pointee.pw_name)
            }
            environment["SHELL"] = shell
            environment["TERM"] = "xterm-256color"
            environment["COLORTERM"] = "truecolor"
            environment["TERM_PROGRAM"] = "GitAgent"
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                environment["TERM_PROGRAM_VERSION"] = version
            }
            if environment["LANG"] == nil {
                environment["LANG"] = Locale.current.identifier + ".UTF-8"
            }
            let environmentPointers: [UnsafeMutablePointer<CChar>?] =
                environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            // Fall back to the user's home directory, like Terminal.app —
            // the app process itself starts in `/`.
            let startDirectory = directory ?? environment["HOME"]
            let directoryPointer = startDirectory.map { strdup($0) }
            defer {
                for case let pointer? in argumentPointers {
                    free(pointer)
                }
                for case let pointer? in environmentPointers {
                    free(pointer)
                }
                if let directoryPointer {
                    free(directoryPointer)
                }
            }

            let pid = argumentPointers.withUnsafeBufferPointer { argumentsBuffer -> pid_t in
                environmentPointers.withUnsafeBufferPointer { environmentBuffer -> pid_t in
                    let child = forkpty(&masterFD, nil, nil, &windowSize)
                    if child == 0 {
                        // Start directly in the target directory instead of
                        // typing a `cd` command into the visible shell.
                        if let directoryPointer {
                            chdir(directoryPointer)
                        }
                        execve(
                            shell,
                            argumentsBuffer.baseAddress!,
                            environmentBuffer.baseAddress!
                        )
                        _exit(127)
                    }
                    return child
                }
            }

            guard pid >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            processID = pid
            let handle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
            masterHandle = handle
            handle.readabilityHandler = { [weak self] readableHandle in
                let data = readableHandle.availableData
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if data.isEmpty {
                        self.finish()
                    } else {
                        self.onOutput?(data)
                    }
                }
            }

            let source = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: .exit,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.finish()
            }
            source.resume()
            processSource = source
            state = .connected
        } catch {
            releaseSecurityScope()
            state = .failed(error.localizedDescription)
        }
    }

    func send(_ data: Data) {
        guard state == .connected, let masterHandle else { return }
        try? masterHandle.write(contentsOf: data)
    }

    func resize(cols: Int, rows: Int) {
        guard let masterHandle, cols > 0, rows > 0 else { return }
        var size = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterHandle.fileDescriptor, TIOCSWINSZ, &size)
    }

    func disconnect() {
        if let processID {
            _ = kill(processID, SIGHUP)
        }
        finish()
    }

    private func beginSecurityScope(_ bookmarkData: Data?) throws {
        guard let bookmarkData else { return }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw RepositoryLocationVerifier.VerificationError.localAccessDenied
        }
        scopedDirectoryURL = url
    }

    private func releaseSecurityScope() {
        scopedDirectoryURL?.stopAccessingSecurityScopedResource()
        scopedDirectoryURL = nil
    }

    private func preferredShell() -> String {
        if let passwd = getpwuid(getuid()),
           let shell = String(validatingCString: passwd.pointee.pw_shell),
           shell.hasPrefix("/"),
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    private func finish() {
        masterHandle?.readabilityHandler = nil
        masterHandle = nil
        processSource?.cancel()
        processSource = nil
        if let processID {
            var status: Int32 = 0
            _ = waitpid(processID, &status, WNOHANG)
        }
        processID = nil
        releaseSecurityScope()
        state = .disconnected
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
#endif
