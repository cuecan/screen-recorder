import Foundation
import Testing
@testable import ProjectKit

@Suite struct ProjectModelTests {
    /// Each shape at the preset heights: the width follows the height, rounded to an even number.
    @Test(arguments: [
        (CaptureArea.Ratio.sixteenByNine, 1080, 1920),
        (.sixteenByNine, 810, 1440),
        (.sixteenByNine, 540, 960),
        (.thirtyTwoByTwentySeven, 1080, 1280),
        (.thirtyTwoByTwentySeven, 810, 960),
        (.thirtyTwoByTwentySeven, 540, 640),
        (.nineBySixteen, 1080, 608),
        (.nineBySixteen, 810, 456),
        (.nineBySixteen, 540, 304),
        (.twentySevenByThirtyTwo, 1080, 912),
        (.twentySevenByThirtyTwo, 810, 684),
        (.twentySevenByThirtyTwo, 540, 456),
        (.nineByEight, 1080, 1216),
        (.nineByEight, 810, 912),
        (.nineByEight, 540, 608),
    ])
    func captureAreaWidthFollowsHeight(ratio: CaptureArea.Ratio, height: Int, width: Int) {
        let area = CaptureArea(ratio: ratio, heightPoints: height)
        #expect(area.widthPoints == width)
        #expect(area.widthPoints.isMultiple(of: 2))
    }

    @Test func theLayoutsShapesAreTheOnlyOnes() {
        #expect(CaptureArea.Ratio.allCases.map(\.rawValue) == ["16:9", "4:3", "32:27", "8:9", "9:16", "3:4", "27:32", "9:8", "1:1"])
        #expect(CaptureArea.Ratio.allCases.allSatisfy { ratio in
            VideoFormat.Destination.allCases.contains { destination in
                TakeLayout.shares(for: destination).contains(ratio) || TakeLayout.card(.bubble).captureRatio(for: destination) == ratio
            }
        }, "Every shape is some layout's.")
        #expect(CaptureArea.Ratio(rawValue: "6:5") == nil)
        #expect(CaptureArea.Ratio(rawValue: "3:2") == nil)
    }

    /// Landscape with a small camera defaults to the largest 16:9 area the display fits.
    @Test(arguments: [
        (2560.0, 1440.0, 2560, 1440),  // A 16:9 display: the whole screen.
        (1512.0, 982.0, 1512, 850),  // A 14" laptop at its default size: full width, trimmed top or bottom.
        (1440.0, 900.0, 1440, 810),  // A 16:10 display.
        (1000.0, 300.0, 534, 300),  // A wide, short window of space: the height limits it.
    ])
    func largestSixteenByNineFits(width: Double, height: Double, areaWidth: Int, areaHeight: Int) throws {
        let area = try #require(CaptureArea.largest(.sixteenByNine, fittingWidth: width, height: height))
        #expect(area.widthPoints == areaWidth)
        #expect(area.heightPoints == areaHeight)
        #expect(area.fits(width: width, height: height))
    }

    @Test func largestWorksForEveryShape() throws {
        for ratio in CaptureArea.Ratio.allCases {
            let area = try #require(CaptureArea.largest(ratio, fittingWidth: 1512, height: 982))
            #expect(area.fits(width: 1512, height: 982), "\(ratio.rawValue) doesn't fit")
            #expect(area.heightPoints.isMultiple(of: 2))
        }
    }

    @Test func noAreaFitsNoSpace() {
        #expect(CaptureArea.largest(.nineByEight, fittingWidth: 1, height: 1) == nil)
    }

    @Test func presetHeightsThatDontFitAreReported() {
        // 1080 pt doesn't fit a 14" laptop's 982 pt height, whatever the shape.
        #expect(!CaptureArea(ratio: .nineByEight, heightPoints: 1080).fits(width: 1512, height: 982))
        #expect(CaptureArea(ratio: .nineByEight, heightPoints: 810).fits(width: 1512, height: 982))
        // A 16:9 area 810 pt high is 1440 pt wide, which fits; 1080 pt high is 1920 wide, which doesn't.
        #expect(!CaptureArea(ratio: .sixteenByNine, heightPoints: 1080).fits(width: 1512, height: 1200))
    }

    @Test func addingSourcesNumbersThem() {
        var project = Project(title: "Test")
        let first = project.addSource(name: "A", origin: .recorded, tracks: [])
        let second = project.addSource(name: "B", origin: .imported, tracks: [])
        #expect(first.id == SourceID(number: 1))
        #expect(second.id == SourceID(number: 2))
        #expect(project.nextSourceNumber == 3)
        #expect(project.source(SourceID(number: 2))?.name == "B")
        #expect(project.source(SourceID(number: 3)) == nil)
    }

    @Test func screenRecordingHearsItsMic() {
        let source = Source(
            id: SourceID(number: 1),
            name: "Screen recording",
            origin: .recorded,
            tracks: [
                SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 30)),
                SourceTrack(
                    kind: .systemAudio, file: .inProject("recordings/system.m4a"),
                    media: MediaInfo(duration: 30, audio: .init(sampleRate: 48_000, channels: 2, codec: "aac"))
                ),
                SourceTrack(
                    kind: .microphone, file: .inProject("recordings/mic.wav"), startOffset: 0.5,
                    media: MediaInfo(duration: 30, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))
                ),
            ]
        )
        #expect(source.primaryAudioTrack?.kind == .microphone)
        #expect(source.duration == 30, "A source lasts until its first picture or voice track ends (docs/decisions.md, 87).")
        // System audio never shortens it, and alone it's the source's length.
        var shortSound = source
        shortSound.tracks[1].media.duration = 12
        #expect(shortSound.duration == 30)
        shortSound.tracks = [shortSound.tracks[1]]
        #expect(shortSound.duration == 12)
    }

    @Test func importedVideoHearsItsOwnAudio() {
        let source = Source(
            id: SourceID(number: 1),
            name: "IMG_1.MOV",
            origin: .imported,
            tracks: [
                SourceTrack(
                    kind: .video, file: .external(URL(filePath: "/tmp/IMG_1.MOV")),
                    media: MediaInfo(duration: 12, audio: .init(sampleRate: 48_000, channels: 2, codec: "aac"))
                )
            ]
        )
        #expect(source.primaryAudioTrack?.kind == .video)
    }

    @Test func silentVideoHasNoAudioTrack() {
        let source = Source(
            id: SourceID(number: 1), name: "B-roll", origin: .imported,
            tracks: [SourceTrack(kind: .video, file: .external(URL(filePath: "/tmp/b.mov")), media: MediaInfo(duration: 5))]
        )
        #expect(source.primaryAudioTrack == nil)
    }

    @Test func fileReferencesResolveInsideOrOutsideTheProject() {
        let folder = URL(filePath: "/Users/someone/Projects/Test")
        let recorded = FileReference.inProject("recordings/mic.wav")
        #expect(!recorded.isExternal)
        #expect(recorded.url(relativeTo: folder).path() == "/Users/someone/Projects/Test/recordings/mic.wav")

        let imported = FileReference.external(URL(filePath: "/Volumes/Card/DCIM/../DCIM/IMG_1.MOV"))
        #expect(imported.isExternal)
        #expect(imported.path == "/Volumes/Card/DCIM/IMG_1.MOV")
        #expect(imported.url(relativeTo: folder).path() == "/Volumes/Card/DCIM/IMG_1.MOV")
    }

    @Test func draftsTakeIDsFromTheGivenNumbers() {
        let draft = TranscriptDraft(
            engine: "e", silenceDetector: "d", language: nil, audioDuration: 2,
            items: [
                .silence(start: 0, end: 0.5),
                .word(.init(text: "a", start: 0.5, end: 1)),
                .word(.init(text: "b", start: 1, end: 1.5)),
                .silence(start: 1.5, end: 2),
            ]
        )
        let result = draft.assigningIDs(source: SourceID(number: 4), firstWordNumber: 10, firstSilenceNumber: 3)
        #expect(result.transcript.items.map(\.id) == [s(3), w(10), w(11), s(4)])
        #expect(result.nextWordNumber == 12)
        #expect(result.nextSilenceNumber == 5)
        #expect(result.transcript.source == SourceID(number: 4))
        #expect(result.transcript.text == "a b")
    }

    @Test func timeRangeSubtraction() {
        let range = TimeRange(start: 0, end: 10)
        #expect(range.subtracting(TimeRange(start: 2, end: 3)) == [TimeRange(start: 0, end: 2), TimeRange(start: 3, end: 10)])
        #expect(range.subtracting(TimeRange(start: -1, end: 3)) == [TimeRange(start: 3, end: 10)])
        #expect(range.subtracting(TimeRange(start: 8, end: 12)) == [TimeRange(start: 0, end: 8)])
        #expect(range.subtracting(TimeRange(start: -1, end: 11)).isEmpty)
        #expect(range.subtracting(TimeRange(start: 10, end: 12)) == [range], "Touching isn't overlapping.")
        #expect(range.subtracting(TimeRange(start: 5, end: 5)) == [range], "An empty range takes nothing out.")
    }
}
