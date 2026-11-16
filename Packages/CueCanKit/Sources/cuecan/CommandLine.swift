import Foundation
import MCP
import ProcessingKit
import ProjectKit
import RenderKit
import TranscribeKit

/// `cuecan`'s command line. Plain `cuecan` acts like a CLI rather than waiting for MCP messages
/// (docs/decisions.md, 31):
///
///     cuecan mcp                                  the MCP server, on stdin and stdout
///     cuecan tools                                every tool and what it does
///     cuecan <tool> [json] | [--name value …]     run one tool
///     cuecan process <project> [--no-screen-text] transcribe, clean and read the screen
///     cuecan models [download]                    whether the speech models are here; fetch them
enum CuecanCommand {
    static let usage = """
        Usage:
          cuecan mcp                               Run the MCP server for Claude (stdio).
          cuecan tools                             List the tools.
          cuecan <tool> '{"project": "…"}'         Run a tool with JSON arguments.
          cuecan <tool> --project … --start_id …   Or with --name value pairs.
          cuecan --machine <command> …             JSON Lines for process, render, export_timeline, or export_plan <snapshot>.
          cuecan --machine align --project … --start_id … [--end_id …] --text …
                                                   Time a fix's words against the audio, without saving it.
          cuecan process <project>                 Transcribe, clean and read the screen of every source that needs it.
          cuecan models [download]                 Say whether the speech models are on this Mac, or download them.
                         [--no-screen-text]        Don't read the text on screen (the app's Save screen text setting).

        Set it up for Claude Code:
          claude mcp add cuecan-mac -- /Applications/CueCan.app/Contents/Helpers/cuecan mcp
        """

    static func run(_ arguments: [String]) async -> Int32 {
        let machine = arguments.first == "--machine"
        let arguments = machine ? Array(arguments.dropFirst()) : arguments
        guard let command = arguments.first else {
            print(usage)
            return 0
        }
        let rest = Array(arguments.dropFirst())
        do {
            if machine, !["process", "export_plan", "render", "export_timeline", "align", "models"].contains(command) {
                throw ToolError.invalidValue("--machine", "this command has no structured result.")
            }
            switch command {
            case "export_plan" where machine:
                guard let path = rest.first else { throw ToolError.missingArgument("plan") }
                let plan = try ExportPlan.read(from: URL(filePath: path))
                let result = try await ExportTimelineTool.export(plan)
                try emit(.exported(result))
            case "align" where machine:
                let values = ToolArguments(try parse(rest))
                let folder = try ProjectLibrary().find(try values.string("project"))
                let timings = try await FixTimer().timings(for: try values.range(from: "start_id", to: "end_id"), as: try values.string("text"), in: folder)
                try emit(.aligned(timings ?? []))
            case "models":
                // `models` says whether the speech models are here; `models download` fetches what's missing.
                let wantsDownload = rest.first == "download"
                let report: @Sendable (SpeechModelsMessage) -> Void = { message in
                    if machine, let line = try? message.line() { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
                }
                if !wantsDownload {
                    let here = SpeechModels.areDownloaded
                    report(here ? .ready : .missing)
                    if !machine { print(here ? "The speech models are downloaded." : "The speech models aren't downloaded. Run: cuecan models download") }
                    return 0
                }
                do {
                    try await SpeechModels.download { fraction in
                        if machine { report(.progress(fraction)) }
                        else { FileHandle.standardError.write(Data("\(Int(fraction * 100))%\n".utf8)) }
                    }
                } catch {
                    report(.failed(error.localizedDescription))
                    if !machine { FileHandle.standardError.write(Data("cuecan: \(error.localizedDescription)\n".utf8)) }
                    return 1
                }
                report(.ready)
                if !machine { print("The speech models are downloaded.") }
            case "mcp":
                try await MCPServer.run()
            case "tools":
                for tool in ToolCatalog.all {
                    print("\(tool.name)\n  \(tool.description.replacingOccurrences(of: "\n", with: "\n  "))\n")
                }
            case "process":
                guard let reference = rest.first else { throw ToolError.missingArgument("project") }
                let library = ProjectLibrary()
                let folder = try library.find(reference)
                let report = try await SourceProcessor(readsScreenText: !rest.contains("--no-screen-text")).process(folder) { event in
                    if machine { try? emit(.progress(event)) }
                    else { FileHandle.standardError.write(Data((event.message + "\n").utf8)) }
                }
                if machine {
                    try emit(.processed(report))
                    return report.failures.isEmpty ? 0 : 1
                }
                print("Transcribed \(report.transcribed.count), spelled \(report.spelled.count), cleaned \(report.cleaned.count), read \(report.screensRead.count) \(report.screensRead.count == 1 ? "screen" : "screens").")
                for (source, reason) in report.failures.sorted(by: { $0.key < $1.key }) { print("\(source): \(reason)") }
                return report.failures.isEmpty ? 0 : 1
            case "help", "--help", "-h":
                print(usage)
            default:
                guard let tool = ToolCatalog.tool(named: command) else { throw ToolError.unknownTool(command) }
                let output = try await tool.run(ToolArguments(try parse(rest)), context: ToolContext(author: .commandLine("cuecan")))
                if machine {
                    guard let result = output.exported else { throw ToolError.invalidValue("--machine", "this command has no structured result.") }
                    try emit(.exported(result))
                    return 0
                }
                print(output.text)
                if !output.images.isEmpty {
                    let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-stills-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for (index, image) in output.images.enumerated() {
                        let url = folder.appending(path: "still-\(index + 1).jpg")
                        try image.data.write(to: url)
                        print(url.path(percentEncoded: false))
                    }
                }
            }
            return 0
        } catch {
            if machine { try? emit(.failed(error.localizedDescription)) }
            else { FileHandle.standardError.write(Data("cuecan: \(error.localizedDescription)\n".utf8)) }
            return 1
        }
    }

    private static func emit(_ message: HelperMessage) throws {
        FileHandle.standardOutput.write(Data((try message.line() + "\n").utf8))
    }

    /// Arguments as one JSON object, or as `--name value` pairs. A value that reads as JSON (a number, true,
    /// a list, an object) is taken as that; anything else is a string.
    static func parse(_ arguments: [String]) throws -> [String: Value] {
        if arguments.count == 1, let first = arguments.first, first.hasPrefix("{") {
            do {
                return try JSONDecoder().decode([String: Value].self, from: Data(first.utf8))
            } catch {
                throw ToolError.invalidJSON(error.localizedDescription)
            }
        }
        var values: [String: Value] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard flag.hasPrefix("--") else { throw ToolError.invalidValue(flag, "expected --name value.") }
            let name = String(flag.dropFirst(2))
            let value = index + 1 < arguments.count && !arguments[index + 1].hasPrefix("--") ? arguments[index + 1] : "true"
            index += value == "true" && (index + 1 >= arguments.count || arguments[index + 1].hasPrefix("--")) ? 1 : 2
            if let data = value.data(using: .utf8), let parsed = try? JSONDecoder().decode(Value.self, from: data), parsed.stringValue == nil {
                values[name] = parsed
            } else {
                values[name] = .string(value)
            }
        }
        return values
    }
}
