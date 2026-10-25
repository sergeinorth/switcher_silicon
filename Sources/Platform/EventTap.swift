import AppKit
import Carbon

public protocol EventTapDelegate: AnyObject {
    func eventTap(didReceiveKeyDown keyCode: UInt16, characters: String, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>?
}

public final class EventTap {
    public weak var delegate: EventTapDelegate?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionDownAt: CFAbsoluteTime?
    private var optionAlone = false

    public init() {}

    public var isEnabled: Bool { port != nil }

    @discardableResult
    public func start() -> Bool {
        stop()

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        port = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        port = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if EventSynth.isOurs(event) {
            return Unmanaged.passUnretained(event)
        }

        if SecureInput.isEnabled {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let chars = characters(from: event)
            return delegate?.eventTap(didReceiveKeyDown: keyCode, characters: chars, flags: flags, event: event)
                ?? Unmanaged.passUnretained(event)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return delegate?.eventTap(didReceiveKeyUp: keyCode, flags: event.flags, event: event)
                ?? Unmanaged.passUnretained(event)
        case .flagsChanged:
            trackOptionTap(event)
            return delegate?.eventTapDidReceiveFlagsChanged(event: event)
                ?? Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Detects a quick left/right Option press-and-release with no other keys.
    public private(set) var pendingOptionTap = false

    public func consumeOptionTap() -> Bool {
        defer { pendingOptionTap = false }
        return pendingOptionTap
    }

    private func trackOptionTap(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isOptionKey = keyCode == 58 || keyCode == 61 // left / right Option
        guard isOptionKey else {
            if optionDownAt != nil {
                optionAlone = false
            }
            return
        }

        let optionDown = flags.contains(.maskAlternate)
        if optionDown {
            optionDownAt = CFAbsoluteTimeGetCurrent()
            optionAlone = true
            pendingOptionTap = false
        } else if let started = optionDownAt {
            let duration = CFAbsoluteTimeGetCurrent() - started
            if optionAlone && duration < 0.45 {
                pendingOptionTap = true
            }
            optionDownAt = nil
            optionAlone = false
        }
    }

    private func characters(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: Int(length))
    }
}
