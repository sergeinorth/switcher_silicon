import AppKit
import Carbon
import Engine

public protocol EventTapDelegate: AnyObject {
    func eventTap(didReceiveKeyDown keyCode: UInt16, characters: String, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>?
    func eventTapDidDetectOptionTap()
    /// Option(+Shift) teach chord — or undo last teach when idle.
    func eventTapDidDetectOptionShiftTap()
    func eventTapDidDetectPauseChord()
}

public final class EventTap {
    public weak var delegate: EventTapDelegate?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionDownAt: CFAbsoluteTime?
    private var optionAlone = false
    private var optionWithShift = false
    private var optionKeyCode: UInt16 = 58
    private var leftShiftDown = false
    private var rightShiftDown = false
    private var bothShiftsFired = false

    public var convertChord: ModifierChord = .eitherOption
    public var teachChord: ModifierChord = .optionShift
    public var pauseChord: ModifierChord = .bothShifts

    public init() {}

    public var isEnabled: Bool { port != nil }

    public func applyHotkeys(_ prefs: HotkeyPrefs) {
        convertChord = prefs.convert
        teachChord = prefs.teach
        pauseChord = prefs.pause
    }

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
            trackModifiers(event)
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

    private func trackModifiers(_ event: CGEvent) {
        if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            cancelOptionAlone()
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Both Shifts pause chord.
        if keyCode == 56 || keyCode == 60 {
            let shiftDown = flags.contains(.maskShift)
            if keyCode == 56 { leftShiftDown = shiftDown }
            if keyCode == 60 { rightShiftDown = shiftDown }
            if leftShiftDown, rightShiftDown {
                if !bothShiftsFired, pauseChord == .bothShifts {
                    bothShiftsFired = true
                    nonisolated(unsafe) let del = self.delegate
                    DispatchQueue.main.async {
                        del?.eventTapDidDetectPauseChord()
                    }
                }
            } else {
                bothShiftsFired = false
            }
        }

        if isOptionKeyCode(keyCode) {
            let optionDown = flags.contains(.maskAlternate)
            if optionDown {
                optionDownAt = CFAbsoluteTimeGetCurrent()
                optionAlone = true
                optionWithShift = flags.contains(.maskShift)
                optionKeyCode = UInt16(keyCode)
            } else {
                finishOptionIfAlone()
            }
            return
        }

        if optionDownAt != nil, flags.contains(.maskAlternate), flags.contains(.maskShift) {
            optionWithShift = true
        }
    }

    private func matches(_ chord: ModifierChord, shift: Bool, keyCode: UInt16) -> Bool {
        guard chord != .disabled else { return false }
        guard chord.isOptionBased else { return false }
        if chord.wantsShift != shift { return false }
        if let required = chord.requiredOptionKeyCode, required != keyCode { return false }
        return true
    }

    private func finishOptionIfAlone() {
        guard let started = optionDownAt else { return }
        let duration = CFAbsoluteTimeGetCurrent() - started
        let alone = optionAlone
        let shift = optionWithShift
        let keyCode = optionKeyCode
        optionDownAt = nil
        optionAlone = false
        optionWithShift = false
        if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            return
        }
        guard alone, duration < 0.60 else { return }

        nonisolated(unsafe) let del = self.delegate
        let teachHit = matches(teachChord, shift: shift, keyCode: keyCode)
        let convertHit = matches(convertChord, shift: shift, keyCode: keyCode)
        DispatchQueue.main.async {
            if EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
                return
            }
            if teachHit {
                del?.eventTapDidDetectOptionShiftTap()
            } else if convertHit {
                del?.eventTapDidDetectOptionTap()
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
