import Foundation
import ProjectKit
import Testing
@testable import RenderKit

/// Regressions for the warnings observed when importing a real CueCan export in Final Cut Pro 12.4.
struct FCPXMLCompatibilityTests {
    @Test func projectsDeclareTheirWorkingSpaceWithoutRelabellingRawMediaOrChangingMonoAssets() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-fcpxml-compatibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "XML compatibility")
        let project = try folder.updateProject { project in
            project.format = VideoFormat(destination: .both)
            project.addSource(name: "QA recording", origin: .recorded, tracks: [
                SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), startOffset: 0,
                            media: MediaInfo(duration: 5, video: .init(width: 1920, height: 1080, frameRate: 60, captureRate: 60, codec: "hvc1"))),
                SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), startOffset: 0,
                            media: MediaInfo(duration: 5, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
                SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), startOffset: 0,
                            media: MediaInfo(duration: 5, audio: .init(sampleRate: 48_000, channels: 1, codec: "pcm")))
            ])
        }
        let source = try #require(project.sources.first)
        try folder.updateEdit(author: .app, reason: "Fixture") { $0.addWholeSource(source) }
        let xml = try FCPXMLWriter.document(RenderInputs.load(folder), options: .init(outputs: [.landscape, .vertical]))
        let document = try XMLDocument(xmlString: xml)
        let formats = Dictionary(uniqueKeysWithValues: try document.nodes(forXPath: "/fcpxml/resources/format").compactMap { node -> (String, XMLElement)? in
            guard let element = node as? XMLElement, let id = element.attribute(forName: "id")?.stringValue else { return nil }
            return (id, element)
        })
        let sequences = try document.nodes(forXPath: "//sequence").compactMap { $0 as? XMLElement }
        #expect(sequences.count == 2)
        var projectFormats = Set<String>()
        for sequence in sequences {
            #expect(sequence.attribute(forName: "audioLayout")?.stringValue == "stereo")
            let id = try #require(sequence.attribute(forName: "format")?.stringValue)
            projectFormats.insert(id)
            let format = try #require(formats[id])
            #expect(format.attribute(forName: "colorSpace")?.stringValue == "1-1-1 (Rec. 709)")
            #expect(format.attribute(forName: "frameDuration")?.stringValue == "1/60s")
        }
        for asset in try document.nodes(forXPath: "/fcpxml/resources/asset").compactMap({ $0 as? XMLElement }) {
            if let id = asset.attribute(forName: "format")?.stringValue {
                #expect(!projectFormats.contains(id))
                #expect(formats[id]?.attribute(forName: "colorSpace") == nil)
            }
            if asset.attribute(forName: "hasAudio")?.stringValue == "1" {
                #expect(asset.attribute(forName: "audioChannels")?.stringValue == "1")
            }
        }
        #expect(!xml.contains("FFVideoFormatRateUndefined"))
    }
}
