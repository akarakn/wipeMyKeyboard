import Darwin
import Foundation

@main
struct WipeMyKeyboardCLI {
    private static let responseTimeout: TimeInterval = 5

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments == ["--help"] || arguments == ["-h"] {
            printUsage()
            exit(EXIT_SUCCESS)
        }

        guard
            arguments.count == 1,
            let command = command(for: arguments[0])
        else {
            printUsage(toStandardError: true)
            exit(EXIT_FAILURE)
        }

        do {
            let response = try send(command)
            print(response.message)
            exit(response.success ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            writeToStandardError("wipemykeyboard: \(error.localizedDescription)\n")
            exit(EXIT_FAILURE)
        }
    }

    private static func command(for argument: String) -> CLIControlCommand? {
        switch argument {
        case "--lock":
            return .lock
        case "--unlock":
            return .unlock
        case "--status":
            return .status
        default:
            return nil
        }
    }

    private static func send(
        _ command: CLIControlCommand
    ) throws -> CLIControlResponse {
        try CLIControlProtocol.prepareControlDirectory()

        let request = CLIControlRequest(id: UUID(), command: command)
        let requestURL = CLIControlProtocol.requestURL(for: request.id)
        let responseURL = CLIControlProtocol.responseURL(for: request.id)
        let requestData = try JSONEncoder().encode(request)

        try requestData.write(to: requestURL, options: .atomic)
        CLIControlProtocol.notifyApp()

        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: responseURL.path) {
                let responseData = try Data(contentsOf: responseURL)
                let response = try JSONDecoder()
                    .decode(CLIControlResponse.self, from: responseData)

                try? FileManager.default.removeItem(at: responseURL)
                return response
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        try? FileManager.default.removeItem(at: requestURL)
        throw CLIError.appUnavailable
    }

    private static func printUsage(toStandardError: Bool = false) {
        let usage = """
        Usage: wipemykeyboard --lock | --unlock | --status

          --lock    Lock the selected input devices
          --unlock  Unlock all input devices
          --status  Print the current lock status
        """

        if toStandardError {
            writeToStandardError(usage + "\n")
        } else {
            print(usage)
        }
    }

    private static func writeToStandardError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    private enum CLIError: LocalizedError {
        case appUnavailable

        var errorDescription: String? {
            switch self {
            case .appUnavailable:
                return "the menu bar app is not running or did not respond"
            }
        }
    }
}
