import AppKit
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
            fileName = settings.soundPrefs.switchToRussian
        case .switchToEnglish:
            mask = .switchToEnglish
            fileName = settings.soundPrefs.switchToEnglish
        case .autoConvert:
            mask = .autoConvert
            fileName = settings.soundPrefs.autoConvert
        case .undo:
            mask = .undo
            fileName = settings.soundPrefs.undo
        case .selectionConvert:
            mask = .selectionConvert
            fileName = settings.soundPrefs.selectionConvert
        }

        guard settings.sounds.contains(mask) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.playNamed(fileName)
        }
    }

    public func preview(named name: String) {
        DispatchQueue.main.async { [weak self] in
            self?.playNamed(name)
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
        NSSound.beep()
    }
}
