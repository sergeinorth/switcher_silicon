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

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func play(_ event: SoundEvent) {
        guard settings.isSoundOn else { return }

        let mask: SoundMask
        let systemSoundID: SystemSoundID
        switch event {
        case .switchToRussian:
            mask = .switchToRussian
            systemSoundID = 1057 // Tink
        case .switchToEnglish:
            mask = .switchToEnglish
            systemSoundID = 1057
        case .autoConvert:
            mask = .autoConvert
            systemSoundID = 1104 // Begin recording-ish short click; distinct enough
        case .undo:
            mask = .undo
            systemSoundID = 1053 // Fail / undo-ish
        case .selectionConvert:
            mask = .selectionConvert
            systemSoundID = 1103
        }

        guard settings.sounds.contains(mask) else { return }
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
