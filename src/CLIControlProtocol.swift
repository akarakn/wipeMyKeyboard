import CoreFoundation
import Foundation

enum CLIControlCommand: String, Codable {
    case lock
    case unlock
    case status
}

struct CLIControlRequest: Codable {
    let id: UUID
    let command: CLIControlCommand
}

struct CLIControlResponse: Codable {
    let id: UUID
    let success: Bool
    let message: String
    let isLocked: Bool
}

enum CLIControlProtocol {
    static let notificationName = CFNotificationName(
        rawValue: "com.example.wipeMyKeyboard.cli-command" as CFString
    )

    private static let requestSuffix = ".request.json"
    private static let responseSuffix = ".response.json"

    static var controlDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wipeMyKeyboard", isDirectory: true)
            .appendingPathComponent("CLIControl", isDirectory: true)
    }

    static func prepareControlDirectory() throws {
        let fileManager = FileManager.default
        let directoryURL = controlDirectoryURL

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    static func requestURL(for id: UUID) -> URL {
        controlDirectoryURL
            .appendingPathComponent(id.uuidString + requestSuffix)
    }

    static func responseURL(for id: UUID) -> URL {
        controlDirectoryURL
            .appendingPathComponent(id.uuidString + responseSuffix)
    }

    static func pendingRequestURLs() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: controlDirectoryURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.lastPathComponent.hasSuffix(requestSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func notifyApp() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }
}
