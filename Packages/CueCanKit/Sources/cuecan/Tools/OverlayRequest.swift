import Foundation
import ProjectKit

/// A decoded overlay command. Removal cannot also create, move or replace an overlay.
enum OverlayRequest {
    enum Target {
        case words(ItemRange), timeline(TimeRange)
    }
    struct Changes {
        let media: Overlay.Media?
        let target: Target?
        let placement: Overlay.Placement?
        let muted: Bool?
        let sourceIn: Double?
    }
    case create(media: Overlay.Media, target: Target, placement: Overlay.Placement, muted: Bool, sourceIn: Double)
    case update(ClipID, Changes)
    case remove(ClipID)

    init(_ arguments: ToolArguments) throws {
        let id = try arguments.optionalString("overlay_id").map { text in
            guard let id = ClipID(text) else { throw ToolError.invalidID(text, expected: "an overlay id like c_9") }
            return id
        }
        if try arguments.optionalBool("remove") == true {
            guard let id else { throw ToolError.missingArgument("overlay_id") }
            try arguments.reject(["source_id", "file", "start_word_id", "end_word_id", "start_time", "end_time", "placement", "muted", "source_in"],
                                 because: "removing an overlay cannot also change it.")
            self = .remove(id)
            return
        }
        let source = try arguments.optionalSourceID("source_id")
        let path = try arguments.optionalString("file")
        guard source == nil || path == nil else { throw ToolError.invalidValue("file", "give a source or a file, not both.") }
        let media: Overlay.Media?
        if let source { media = .source(source) }
        else if let path {
            let url = URL(filePath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ToolError.invalidValue("file", "there's no file at \(url.path(percentEncoded: false)).") }
            media = .file(at: url)
        } else { media = nil }
        let target: Target?
        if ["start_word_id", "end_word_id", "start_time", "end_time"].contains(where: arguments.has) {
            switch try EditTarget.read(arguments, firstWord: "start_word_id", lastWord: "end_word_id", sourceKey: nil) {
            case .words(let range): target = .words(range)
            case .timeline(let range): target = .timeline(range)
            case .source: throw ToolError.invalidValue("source_id", "overlay placement uses timeline time.")
            }
        } else { target = nil }
        let placement = try arguments.optionalString("placement").map { name -> Overlay.Placement in
            switch name {
            case "covers_frame": .coversFrame
            case "in_screens_place": .inScreensPlace
            default: throw ToolError.invalidValue("placement", "use covers_frame or in_screens_place.")
            }
        }
        let muted = try arguments.optionalBool("muted")
        let sourceIn = try arguments.optionalDouble("source_in")
        if let sourceIn, sourceIn < 0 { throw ToolError.invalidValue("source_in", "use a nonnegative time.") }
        if let id {
            guard media != nil || target != nil || placement != nil || muted != nil || sourceIn != nil else {
                throw ToolError.missingArgument("a change to the overlay")
            }
            self = .update(id, Changes(media: media, target: target, placement: placement, muted: muted, sourceIn: sourceIn))
        } else {
            guard let media else { throw ToolError.missingArgument("source_id or file") }
            guard let target else { throw ToolError.missingArgument("start_word_id or start_time") }
            self = .create(media: media, target: target, placement: placement ?? .coversFrame, muted: muted ?? true, sourceIn: sourceIn ?? 0)
        }
    }

    func validateSources(in project: Project) throws {
        let media: Overlay.Media?
        switch self {
        case .create(let value, _, _, _, _): media = value
        case .update(_, let changes): media = changes.media
        case .remove: media = nil
        }
        if case .source(let id) = media, project.source(id) == nil { throw EditError.unknownSource(id) }
    }
}
