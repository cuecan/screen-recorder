import CoreGraphics
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

struct ClipFramingTests {
    @Test func inPlaceFramingAndAFreshBuildDrawTheSameRecordedRegion() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-crop-pixels-\(UUID())"), title: "Static crop plumbing")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try await SyntheticMedia.writeQuadrants(width: 400, height: 400, seconds: 1, to: folder.url(for: .recordings).appending(path: "screen.mov"))
        let project = try folder.updateProject { project in
            project.addSource(name: "Quadrant fixture", origin: .recorded, tracks: [
                .init(kind: .screen, file: .inProject("recordings/screen.mov"),
                      media: .init(duration: 1, video: .init(width: 400, height: 400, frameRate: 30, captureRate: 30, codec: "avc1"))),
            ])
        }
        let source = try #require(project.sources.first)
        try folder.updateEdit(author: .system("Test"), reason: "Fixture") { edit in
            edit.addWholeSource(source)
            edit.look.inset = .none
            edit.look.rounded = false
        }
        let inputs = try RenderInputs.load(folder)
        let original = try await CompositionBuilder.build(inputs, output: .landscape)
        let before = try #require(try await FrameGrabber.stills(of: original, at: [0.5]).first)
        #expect(SyntheticMedia.pixel(before.jpeg, x: 300, y: 100)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(before.jpeg, x: 700, y: 100)?.isClose(to: SyntheticMedia.blue) == true)
        let changed = inputs.withEdit { $0.main[0].screenTransform = .init(centerX: 0.25, centerY: 0.25, zoom: 2) }
        #expect(changed.differsOnlyInFraming(from: inputs))
        let fast = original.reframed(using: changed)
        #expect(fast.composition === original.composition, "Auditioning a crop must not rebuild media tracks.")
        #expect(fast.audioMix === original.audioMix)
        let rebuilt = try await CompositionBuilder.build(changed, output: .landscape)
        let fastStill = try #require(try await FrameGrabber.stills(of: fast, at: [0.5]).first)
        let freshStill = try #require(try await FrameGrabber.stills(of: rebuilt, at: [0.5]).first)
        for x in [300, 500, 700] {
            for y in [100, 250, 400] {
                #expect(SyntheticMedia.pixel(fastStill.jpeg, x: x, y: y)?.isClose(to: SyntheticMedia.red) == true)
                #expect(SyntheticMedia.pixel(freshStill.jpeg, x: x, y: y)?.isClose(to: SyntheticMedia.red) == true)
            }
        }
        #expect(!inputs.withEdit { $0.main[0].sourceOut = 0.8 }.differsOnlyInFraming(from: inputs))
        #expect(!inputs.withEdit { $0.main[0].voiceLevel = -6 }.differsOnlyInFraming(from: inputs))
        #expect(!inputs.withEdit { $0.main[0].layout = .camera }.differsOnlyInFraming(from: inputs))
        // Releasing a drag can cancel a poster just as AVFoundation starts preparing its tracks.
        // Each reader owns its composition; cancellation is deliberately timed around start().
        for index in 0..<80 {
            let redrawn = original.reframed(using: inputs.withEdit {
                $0.main[0].screenTransform = .init(centerX: index.isMultiple(of: 2) ? -1 : 2,
                                                  centerY: index.isMultiple(of: 3) ? -1 : 2, zoom: 2)
            })
            let independent = try redrawn.copyForReading()
            let read = Task { try await FrameGrabber.stills(of: independent, at: [0.5]) }
            if index.isMultiple(of: 4) { await Task.yield() }
            else { try await Task.sleep(for: .microseconds(200 * (index % 5))) }
            read.cancel()
            _ = try? await read.value
        }
    }

    @Test func everyLayoutKeepsItsTilesAndCropsWithinThePicture() throws {
        for destination in VideoFormat.Destination.allCases {
            for preset in takeLayouts(for: destination) {
                let pictures = ClipPictures(screen: CGSize(width: preset.captureRatio(for: destination).aspect * 1080, height: 1080),
                                            camera: CGSize(width: 1920, height: 1080), recordedLayout: preset)
                for output in OutputShape.allCases {
                    for layout in [Layout.automatic, .camera, .screen, preset.layout] {
                        let plain = LayoutGeometry.frame(for: layout, in: output, pictures: pictures)
                        let enlarged = LayoutGeometry.frame(for: layout, in: output, pictures: pictures,
                            screenTransform: .init(centerX: 0.98, centerY: 0.02, zoom: 2),
                            cameraTransform: .init(centerX: 0.1, centerY: 0.9, zoom: 2.5))
                        #expect(plain.placements.count == enlarged.placements.count)
                        for (original, changed) in zip(plain.placements, enlarged.placements) {
                            #expect(original.frame == changed.frame)
                            #expect(original.corners == changed.corners)
                            #expect(changed.crop.minX >= 0 && changed.crop.maxX <= 1.000_001)
                            #expect(changed.crop.minY >= 0 && changed.crop.maxY <= 1.000_001)
                            let source = changed.role == .screen ? try #require(pictures.screen) : try #require(pictures.camera)
                            let cropAspect = changed.crop.width * source.width / (changed.crop.height * source.height)
                            #expect(abs(cropAspect - changed.frame.width / changed.frame.height) < 0.000_001)
                        }
                    }
                }
            }
        }
    }

    @Test func aCameraOverrideReplacesOnlyItsClipAndResetReturnsToTheSlotDefault() throws {
        let source = Source(id: SourceID(number: 1), name: "Fixture", origin: .recorded, tracks: [
            .init(kind: .screen, file: .inProject("screen.mov"), media: .init(duration: 10, video: .init(width: 1215, height: 1080, frameRate: 60, captureRate: 60, codec: "hvc1"))),
            .init(kind: .camera, file: .inProject("camera.mov"), media: .init(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
        ], layout: .sideBySide(.nineByEight))
        var edit = Edit(main: [clip(1, 0, 5), clip(2, 5, 10)])
        let baseline = CameraFraming(centerX: 0.35, centerY: 0.45, zoom: 1.2)
        edit.setFraming(baseline, slot: .split, for: source.id)
        let override = PictureTransform(centerX: 0.7, centerY: 0.4, zoom: 2)
        try edit.setTransform(override, picture: .camera, for: [edit.main[0].id])
        for output in OutputShape.allCases {
            #expect(LayoutGeometry.transform(of: .camera, clip: edit.main[0], source: source, edit: edit, in: output) == override)
            #expect(LayoutGeometry.transform(of: .camera, clip: edit.main[1], source: source, edit: edit, in: output) == PictureTransform(baseline))
        }
        try edit.setTransform(nil, picture: .camera, for: [edit.main[0].id])
        #expect(LayoutGeometry.transform(of: .camera, clip: edit.main[0], source: source, edit: edit, in: .landscape) == PictureTransform(baseline))
    }

    @Test func screenAndCameraUseIndependentTransformsInTheHandoff() {
        let pictures = ClipPictures(screen: CGSize(width: 1215, height: 1080), camera: CGSize(width: 1920, height: 1080),
                                    recordedLayout: .sideBySide(.nineByEight))
        for output in OutputShape.allCases {
            let original = LayoutGeometry.frame(for: .automatic, in: output, pictures: pictures)
            let changed = LayoutGeometry.frame(for: .automatic, in: output, pictures: pictures,
                                               screenTransform: .init(centerX: 0.7, zoom: 2))
            #expect(original.placement(.camera) == changed.placement(.camera))
            let size = CGSize(width: output.width, height: output.height)
            if let plain = original.placement(.screen), let zoomed = changed.placement(.screen), let screen = pictures.screen {
                let before = FCPXMLWriter.transform(plain, picture: screen, frame: size)
                let after = FCPXMLWriter.transform(zoomed, picture: screen, frame: size)
                #expect(before != after)
                #expect(after.contains("<adjust-crop"))
            } else { Issue.record("The screen must have a placement.") }
        }
    }
}
