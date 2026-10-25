import AppKit
import AudioToolbox
import Engine

public enum SoundEvent: Sendable {
    case switchToRussian
    case switchToEnglish
    case autoConvert
    case undo
    case selectionConvert
}

public final class SoundPlayer: @unchecked Sendable {
    public var settings: AppSettings
    private var cache: [String: NSSound] = [:]

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func play(_ event: SoundEvent) {
        guard settings.isSoundOn else { return }

        let mask: SoundMask
        let fileName: String
        switch event {
        case .switchToRussian:
            mask = .switchToRussian
            fileName = "Tink" // higher
        case .switchToEnglish:
            mask = .switchToEnglish
            fileName = "Pop"
        case .autoConvert:
            mask = .autoConvert
            fileName = "Tink"
        case .undo:
            mask = .undo
            fileName = "Bottle"
        case .selectionConvert:
            mask = .selectionConvert
            fileName = "Purr"
        }

        guard settings.sounds.contains(mask) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.playNamed(fileName)
        }
    }

    private func playNamed(_ name: String) {
        if let cached = cache[name] {
            cached.stop()
            cached.currentTime = 0
            cached.play()
            return
        }
        let path = "/System/Library/Sounds/\(name).aiff"
        if let sound = NSSound(contentsOfFile: path, byReference: true) {
            cache[name] = sound
            sound.volume = 1.0
            sound.play()
            return
        }
        // Last resort
        NSSound.beep()
    }
}
