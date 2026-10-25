import AppKit
import Engine
import Platform

final class LayoutOrchestrator: EventTapDelegate, @unchecked Sendable {
    private let inputSources = InputSourceManager()
    private let eventTap = EventTap()
    private var soundPlayer: SoundPlayer
    private var settings: AppSettings
    private var checker: LayoutChecker
    private var buffer = KeyStrokeBuffer()
    private var undo = UndoState()
    private var skipNextWord = false
    private var appLayouts: [String: String] = [:]
    private var lastFrontBundle: String?

    var onStatusChange: ((String) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        self.soundPlayer = SoundPlayer(settings: settings)
        self.checker = LayoutChecker(
            neverConvert: [],
            userRules: settings.userRules
        )
        eventTap.delegate = self
        observeAppActivation()
    }

    func start() -> Bool {
        ensureLayoutIDs()
        let ok = eventTap.start()
        onStatusChange?(ok ? "active" : "no-tap")
        return ok
    }

    func stop() {
        eventTap.stop()
        onStatusChange?("stopped")
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        soundPlayer.settings = settings
        checker = LayoutChecker(
            neverConvert: undo.learnedNever,
            userRules: settings.userRules
        )
        SettingsStore.save(settings)
    }

    var currentSettings: AppSettings { settings }

    func toggleAutocorrection() {
        settings.isAutocorrectionActive.toggle()
        reloadSettings(settings)
    }

    // MARK: - EventTapDelegate

    func eventTap(didReceiveKeyDown keyCode: UInt16, characters: String, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isExcludedFrontApp() {
            buffer.clear()
            return Unmanaged.passUnretained(event)
        }

        // Cmd/Ctrl shortcuts — reset buffer, don't convert.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            buffer.clear()
            return Unmanaged.passUnretained(event)
        }

        if WordDetector.isEscape(keyCode) {
            buffer.clear()
            return Unmanaged.passUnretained(event)
        }

        if WordDetector.isBackspace(keyCode) {
            buffer.deleteBackward()
            return Unmanaged.passUnretained(event)
        }

        if WordDetector.isSeparatorKeyCode(keyCode) || characters.contains(where: WordDetector.isSeparator) {
            if scheduleAutoConvertIfNeeded(separatorKeyCode: keyCode, separatorCharacters: characters) {
                // Swallow separator; it will be re-posted after conversion.
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Printable character — accumulate.
        if !characters.isEmpty, !flags.contains(.maskAlternate) || characters != "" {
            // Ignore bare Option (no character) — handled on flagsChanged.
            if flags.contains(.maskAlternate) && characters.isEmpty {
                return Unmanaged.passUnretained(event)
            }
            if !characters.isEmpty {
                for ch in characters {
                    buffer.append(KeyStroke(characters: String(ch), keyCode: keyCode))
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        Unmanaged.passUnretained(event)
    }

    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        if settings.useOptionTrigger, eventTap.consumeOptionTap() {
            // Defer so Option key-up finishes before we synthesize input.
            DispatchQueue.main.async { [weak self] in
                self?.convertLastWord(manual: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Conversion

    /// Returns true when the separator event should be swallowed (conversion scheduled).
    private func scheduleAutoConvertIfNeeded(separatorKeyCode: UInt16, separatorCharacters: String) -> Bool {
        defer { buffer.clear() }

        if skipNextWord {
            skipNextWord = false
            return false
        }

        guard settings.isAutocorrectionActive else { return false }

        if settings.noAutoconvertAfterTabOrEnter,
           separatorKeyCode == 48 || separatorKeyCode == 36 || separatorKeyCode == 76
        {
            return false
        }

        let word = buffer.stringValue
        guard !word.isEmpty else { return false }
        guard checker.check(word) == .incorrect else { return false }

        let sep = separatorCharacters.isEmpty ? " " : separatorCharacters
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.performConversion(of: word, manual: false)
            // Re-type the swallowed separator after the fixed word.
            usleep(10_000)
            EventSynth.typeText(sep)
        }
        return true
    }

    private func convertLastWord(manual: Bool) {
        // Manual Option: convert buffer if present; otherwise try selected text later.
        let word = buffer.stringValue
        if !word.isEmpty {
            performConversion(of: word, manual: true)
            buffer.clear()
            if settings.cancelNextWordAfterManualSwitch {
                skipNextWord = true
            }
            return
        }

        // Empty buffer — convert selected text via clipboard fallback.
        convertSelectionIfAny()
    }

    private func performConversion(of word: String, manual: Bool) {
        let converted = ConversionEngine.convert(word, direction: .auto)
        guard converted != word else { return }

        let toRussian = ConversionEngine.dominantScript(converted) == .cyrillic
            || (ConversionEngine.dominantScript(word) == .latin)

        undo.remember(ConversionSnapshot(
            original: word,
            converted: converted,
            switchedToRussian: toRussian
        ))

        // Switch layout first, then replace text.
        if toRussian {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
            soundPlayer.play(manual ? .switchToRussian : .autoConvert)
        } else {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
            soundPlayer.play(manual ? .switchToEnglish : .autoConvert)
        }

        EventSynth.replaceLastWord(originalLength: word.count, with: converted)
        onStatusChange?(manual ? "manual:\(converted)" : "auto:\(converted)")
    }

    private func convertSelectionIfAny() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        // Copy selection
        EventSynth.postKey(keyCode: 8, keyDown: true, flags: .maskCommand) // C
        EventSynth.postKey(keyCode: 8, keyDown: false, flags: .maskCommand)
        usleep(40_000)

        guard let selected = pasteboard.string(forType: .string), !selected.isEmpty else {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
            return
        }

        let converted = ConversionEngine.convert(selected, direction: .auto)
        guard converted != selected else {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
            return
        }

        let toRussian = ConversionEngine.dominantScript(converted) == .cyrillic
        if toRussian {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        } else {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        }

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        EventSynth.postKey(keyCode: 9, keyDown: true, flags: .maskCommand) // V
        EventSynth.postKey(keyCode: 9, keyDown: false, flags: .maskCommand)
        soundPlayer.play(.selectionConvert)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    func undoLastConversion() {
        guard let last = undo.last else { return }
        // Replace converted with original: user must be at end of converted word.
        EventSynth.replaceLastWord(originalLength: last.converted.count, with: last.original)
        if last.switchedToRussian {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        } else {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        }
        soundPlayer.play(.undo)
        undo.learnNever(last.original)
        checker = LayoutChecker(neverConvert: undo.learnedNever, userRules: settings.userRules)
        undo.clearLast()
    }

    func changeCaseOfBufferOrSelection() {
        let word = buffer.stringValue
        if !word.isEmpty {
            let toggled = ConversionEngine.toggleCase(word)
            EventSynth.replaceLastWord(originalLength: word.count, with: toggled)
            buffer.clear()
            return
        }
        // Selection via clipboard
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        EventSynth.postKey(keyCode: 8, keyDown: true, flags: .maskCommand)
        EventSynth.postKey(keyCode: 8, keyDown: false, flags: .maskCommand)
        usleep(40_000)
        guard let selected = pasteboard.string(forType: .string), !selected.isEmpty else { return }
        let toggled = ConversionEngine.toggleCase(selected)
        pasteboard.clearContents()
        pasteboard.setString(toggled, forType: .string)
        EventSynth.postKey(keyCode: 9, keyDown: true, flags: .maskCommand)
        EventSynth.postKey(keyCode: 9, keyDown: false, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    // MARK: - Helpers

    private func ensureLayoutIDs() {
        var updated = settings
        if updated.russianLayoutID.isEmpty, let id = inputSources.preferRussianID() {
            updated.russianLayoutID = id
        }
        if updated.englishLayoutID.isEmpty, let id = inputSources.preferEnglishID() {
            updated.englishLayoutID = id
        }
        if updated != settings {
            reloadSettings(updated)
        }
    }

    private func isExcludedFrontApp() -> Bool {
        guard let bundle = FrontmostApp.bundleID else { return false }
        return settings.excludedApps.contains(bundle)
    }

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.handleAppActivation(note)
        }
    }

    private func handleAppActivation(_ note: Notification) {
        guard settings.rememberLayoutPerApp else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundle = app.bundleIdentifier
        else { return }

        if let previous = lastFrontBundle {
            appLayouts[previous] = inputSources.currentSourceID
        }
        lastFrontBundle = bundle
        buffer.clear()

        if let saved = appLayouts[bundle], !saved.isEmpty {
            _ = inputSources.select(sourceID: saved)
        }
    }
}
