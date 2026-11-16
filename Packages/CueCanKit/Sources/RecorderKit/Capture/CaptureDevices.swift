import AVFoundation
import Foundation

/// The cameras and mics connected now, for the widget's pickers.
public struct CaptureDevice: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ device: AVCaptureDevice) {
        id = device.uniqueID
        name = device.localizedName
    }
}

public enum CaptureDevices {
    public static var cameras: [CaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.map(CaptureDevice.init)
    }

    public static var microphones: [CaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map(CaptureDevice.init)
    }

    public static var defaultCamera: CaptureDevice? {
        AVCaptureDevice.default(for: .video).map(CaptureDevice.init)
    }

    public static var defaultMicrophone: CaptureDevice? {
        AVCaptureDevice.default(for: .audio).map(CaptureDevice.init)
    }

    /// Asks for camera or mic access the first time, and says whether it's allowed.
    public static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: mediaType)
        default: false
        }
    }
}
