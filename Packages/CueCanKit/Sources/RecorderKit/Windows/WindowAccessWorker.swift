import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Accessibility messaging is serialized away from the UI. A slow app cannot freeze the setup panel.
actor WindowAccessWorker {
    /// AX references are immutable handles. Only this worker sends messages to them.
    final class Handle: @unchecked Sendable {
        let element: AXUIElement
        init(_ element: AXUIElement) {
            self.element = element
            AXUIElementSetMessagingTimeout(element, 0.2)
        }
    }

    func resolve(_ window: SnappableWindow, reference: CGRect) -> Handle? {
        let app = AXUIElementCreateApplication(window.processID)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return nil }
        let candidates = elements.map { Handle($0) }.filter { handle in
            frame(handle).map { WindowFit.fills($0, area: reference) } ?? false
        }
        let named = candidates.filter { !window.title.isEmpty && title($0) == window.title }
        if named.count == 1 { return named.first }
        if candidates.count == 1 { return candidates.first }
        // A frame may have moved again between the Window Server read and the AX reply. A unique title
        // is still a safe match; an ambiguous title or partial frame is not.
        let titles = elements.map { Handle($0) }.filter { !window.title.isEmpty && title($0) == window.title }
        return titles.count == 1 ? titles.first : nil
    }

    func focused(in process: pid_t) -> Handle? {
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return Handle(unsafeDowncast(value, to: AXUIElement.self))
            }
        }
        return nil
    }

    func isFullScreen(_ handle: Handle) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(handle.element, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue == true
    }

    func frame(_ handle: Handle) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(handle.element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(handle.element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func resize(_ handle: Handle, to frame: CGRect) {
        guard !Task.isCancelled else { return }
        setSize(handle, frame.size)
    }

    func move(_ handle: Handle, to position: CGPoint) {
        guard !Task.isCancelled else { return }
        var position = position
        if let value = AXValueCreate(.cgPoint, &position) {
            let answer = AXUIElementSetAttributeValue(handle.element, kAXPositionAttribute as CFString, value)
            if answer != .success {
                WindowSnapper.log.notice("Moving to \(Int(position.x)),\(Int(position.y)) was answered with \(Self.name(of: answer), privacy: .public)")
            }
        }
    }

    private func setSize(_ handle: Handle, _ size: CGSize) {
        guard !Task.isCancelled else { return }
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            let answer = AXUIElementSetAttributeValue(handle.element, kAXSizeAttribute as CFString, value)
            if answer != .success {
                WindowSnapper.log.notice("Resizing to \(Int(size.width))×\(Int(size.height)) was answered with \(Self.name(of: answer), privacy: .public)")
            }
        }
    }

    /// An Accessibility answer in words. "No answer in time" is an app too busy to reply within the
    /// messaging timeout, which the request may still reach.
    private static func name(of error: AXError) -> String {
        switch error {
        case .success: "success"
        case .cannotComplete: "no answer in time (cannotComplete)"
        case .attributeUnsupported: "attribute unsupported"
        case .illegalArgument: "illegal argument"
        case .invalidUIElement: "the window is gone (invalidUIElement)"
        case .notImplemented: "not implemented"
        case .apiDisabled: "no Accessibility access (apiDisabled)"
        case .failure: "failure"
        default: "AXError \(error.rawValue)"
        }
    }

    private func title(_ handle: Handle) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(handle.element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
