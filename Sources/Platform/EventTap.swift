import AppKit
import Carbon

public protocol EventTapDelegate: AnyObject {
    func eventTap(didReceiveKeyDown keyCode: UInt16, characters: String, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTapDidDetectOptionTap()
    /// Option+Shift quick tap — teach spell replacement (typo → fix).
    func eventTapDidDetectOptionShiftTap()
}

public final class EventTap {
    public weak var delegate: EventTapDelegate?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionDownAt: CFAbsoluteTime?
    private var optionAlone = false
    /// Shift held with Option (teach chord).
    private var optionWithShift = false

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

        // Synthetic Option+Delete (word erase) must not look like a user Option tap —
        // otherwise we auto-convert then immediately toggle/revert ("works every other time").
        if EventSynth.isOurs(event) || EventSynth.isSynthesizing {
            cancelOptionAlone()
            return Unmanaged.passUnretained(event)
        }

        if SecureInput.isEnabled {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            // Real keys cancel Option-alone; Shift is part of the teach chord.
            if optionDownAt != nil, !isOptionKeyCode(keyCode), !isShiftKeyCode(keyCode) {
                optionAlone = false
            }
            if optionDownAt != nil, isShiftKeyCode(keyCode) {
                optionWithShift = true
            }
            let flags = event.flags
            let chars = characters(from: event)
            return delegate?.eventTap(didReceiveKeyDown: keyCode, characters: chars, flags: flags, event: event)
                ?? Unmanaged.passUnretained(event)
        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if isOptionKeyCode(keyCode) {
                finishOptionIfAlone()
            }
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

    private func isOptionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == 58 || keyCode == 61
    }

    private func isOptionKeyCode(_ keyCode: Int64) -> Bool {
        keyCode == 58 || keyCode == 61
    }

    private func isShiftKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == 56 || keyCode == 60
    }

    private func cancelOptionAlone() {
        optionDownAt = nil
        optionAlone = false
        optionWithShift = false
    }

    private func trackOptionTap(_ event: CGEvent) {
        if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            cancelOptionAlone()
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if isOptionKeyCode(keyCode) {
            let optionDown = flags.contains(.maskAlternate)
            if optionDown {
                optionDownAt = CFAbsoluteTimeGetCurrent()
                optionAlone = true
                optionWithShift = flags.contains(.maskShift)
            } else {
                finishOptionIfAlone()
            }
            return
        }

        // Shift while Option is held → teach chord.
        if optionDownAt != nil, flags.contains(.maskAlternate), flags.contains(.maskShift) {
            optionWithShift = true
        }
    }

    private func finishOptionIfAlone() {
        guard let started = optionDownAt else { return }
        let duration = CFAbsoluteTimeGetCurrent() - started
        optionDownAt = nil
        let alone = optionAlone
        let teach = optionWithShift
        optionAlone = false
        optionWithShift = false
        if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            return
        }
        // Up to 0.6s quick tap, no other keys (Shift allowed for teach).
        if alone && duration < 0.60 {
            nonisolated(unsafe) let del = self.delegate
            DispatchQueue.main.async {
                if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
                    return
                }
                if teach {
                    del?.eventTapDidDetectOptionShiftTap()
                } else {
                    del?.eventTapDidDetectOptionTap()
                }
            }
        }
    }

    private func characters(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: Int(length))
    }
}
