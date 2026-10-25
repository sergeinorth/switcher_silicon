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
    private var isConverting = false
    private var conversionGeneration = 0
    private var lastBufferedWord = ""
    /// Last finished word (after space) — Option can still force-convert it.
    private var lastFinishedWord = ""
    private var lastCheckResult = "—"
    private var keyEventCount = 0

    var onStatusChange: ((String) -> Void)?
    var isTapActive: Bool { eventTap.isEnabled }

    init(settings: AppSettings) {
        self.settings = settings
        self.soundPlayer = SoundPlayer(settings: settings)
        self.checker = LayoutChecker(
            validator: SystemWordValidator(),
            neverConvert: [],
            userRules: settings.userRules
        )
        eventTap.delegate = self
        observeAppActivation()
    }

    func start() -> Bool {
        ensureLayoutIDs()
        let ok = eventTap.start()
        AppLog.line("eventTap.start => \(ok), layout=\(inputSources.currentSourceID)")
        onStatusChange?(ok ? "active" : "no-tap")
        return ok
    }

    func stop() {
        eventTap.stop()
        onStatusChange?("stopped")
    }

    func diagnostics() -> String {
        return """
        \(AccessibilityPermission.diagnosticsLine)
        Event tap: \(eventTap.isEnabled ? "ok" : "NO")
        Autocorrect: \(settings.isAutocorrectionActive ? "on" : "off")
        Layout: \(inputSources.currentSourceID)
        Front app: \(FrontmostApp.bundleID ?? "?")
        Keys seen: \(keyEventCount)
        Last buffer: «\(lastBufferedWord)»
        Last check: \(lastCheckResult)
        Excluded: \(settings.excludedApps.joined(separator: ", "))
        Log: ~/Library/Logs/SwitcherSilicon.log

        Нужны: Мониторинг ввода + Универсальный доступ для /Applications/SwitcherSilicon.app
        RuSwitcher держи выключенным.
        """
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        soundPlayer.settings = settings
        checker = LayoutChecker(
            validator: SystemWordValidator(),
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
        keyEventCount += 1

        if isExcludedFrontApp() {
            buffer.clear()
            return Unmanaged.passUnretained(event)
        }

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

        let busy = isConverting || EventSynth.isSynthesizing

        // Auto-convert ONLY on Space / Tab / Enter (not on , . ; which are RU letters).
        if WordDetector.isSeparatorKeyCode(keyCode) {
            if busy {
                // Defer: remember separator until replace finishes would be complex;
                // just keep buffering after space by clearing — space already typed.
                buffer.clear()
            } else {
                scheduleAutoConvertAfterSeparator(separatorKeyCode: keyCode)
            }
            return Unmanaged.passUnretained(event)
        }

        if flags.contains(.maskAlternate) && characters.isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let shift = flags.contains(.maskShift)
        if let glyph = resolvedGlyph(characters: characters, keyCode: keyCode, shift: shift) {
            buffer.append(KeyStroke(characters: glyph, keyCode: keyCode))
            lastBufferedWord = buffer.stringValue
        }

        return Unmanaged.passUnretained(event)
    }

    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        Unmanaged.passUnretained(event)
    }

    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        Unmanaged.passUnretained(event)
    }

    func eventTapDidDetectOptionTap() {
        guard settings.useOptionTrigger else { return }
        AppLog.line("option tap buffer=«\(buffer.stringValue)» last=«\(lastFinishedWord)»")
        // Slight delay so Option key-up settles before we synthesize.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.convertLastWord(manual: true)
        }
    }

    /// Prefer event unicode; fall back to US keycode map (event unicode is often empty in taps).
    private func resolvedGlyph(characters: String, keyCode: UInt16, shift: Bool) -> String? {
        if characters.count == 1, let ch = characters.first, isBufferableGlyph(ch) {
            return String(ch)
        }
        if characters.count > 1 {
            let filtered = characters.filter(isBufferableGlyph)
            return filtered.isEmpty ? nil : String(filtered)
        }
        return KeyCodeMap.usCharacter(keyCode: keyCode, shift: shift)
    }

    private func isBufferableGlyph(_ ch: Character) -> Bool {
        if WordDetector.isSeparator(ch) { return false }
        // Drop control / zero-width junk that was polluting «ghbdtn» checks.
        if ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        return ch.isLetter
            || ch == "-" || ch == "—" || ch == "–"
            || ch == "," || ch == "." || ch == ";" || ch == "'" || ch == "[" || ch == "]" || ch == "`"
            || ch == "<" || ch == ">" || ch == ":" || ch == "\"" || ch == "{" || ch == "}" || ch == "~"
    }

    // MARK: - Conversion

    private func scheduleAutoConvertAfterSeparator(separatorKeyCode: UInt16) {
        let word = buffer.stringValue
        buffer.clear()
        lastBufferedWord = word

        if skipNextWord {
            skipNextWord = false
            AppLog.line("skip next word after manual")
            return
        }
        guard settings.isAutocorrectionActive else {
            AppLog.line("auto off, word=\(word)")
            return
        }
        if settings.noAutoconvertAfterTabOrEnter,
           separatorKeyCode == 48 || separatorKeyCode == 36 || separatorKeyCode == 76
        {
            return
        }
        lastFinishedWord = word
        guard word.count >= 2 else {
            AppLog.line("word too short «\(word)»")
            return
        }
        let check = checker.check(word)
        lastCheckResult = "\(check) for «\(word)»"
        AppLog.line("check \(lastCheckResult)")
        guard check == .incorrect else { return }

        let converted = ConversionEngine.convert(word, direction: .auto)
        guard converted != word else { return }
        AppLog.line("schedule convert «\(word)» -> «\(converted)»")

        let sep = WordDetector.separatorString(forKeyCode: separatorKeyCode)
        // For Return/Tab, deleting a newline/tab by character count is unreliable —
        // only auto-replace on Space for now; still switch layout? Skip non-space.
        guard separatorKeyCode == 49 else {
            // Tab/Enter: convert word only (no sep in delete count); sep already typed.
            conversionGeneration += 1
            let generation = conversionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, generation == self.conversionGeneration else { return }
                // Cursor is after newline; deleteCount = word only won't remove newline.
                // Move: not handled — require Space for auto. Manual Option still works.
            }
            return
        }

        conversionGeneration += 1
        let generation = conversionGeneration
        let deleteCount = word.count + 1 // word + space

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard generation == self.conversionGeneration else { return }
            self.performReplacement(
                original: word,
                converted: converted,
                deleteCount: deleteCount,
                suffix: sep,
                manual: false
            )
        }
    }

    private func convertLastWord(manual: Bool) {
        guard !isConverting else {
            AppLog.line("option ignored: busy converting")
            return
        }

        // Prefer live buffer; else last word before space (cursor is after that word+space).
        let fromBuffer = buffer.stringValue
        let word: String
        let deleteCount: Int
        let suffix: String
        if fromBuffer.count >= 1 {
            word = fromBuffer
            deleteCount = word.count
            suffix = ""
            buffer.clear()
        } else if lastFinishedWord.count >= 1 {
            word = lastFinishedWord
            deleteCount = word.count + 1 // word + trailing space
            suffix = " "
            lastFinishedWord = ""
        } else {
            AppLog.line("option: empty buffer — try selection")
            convertSelectionIfAny()
            return
        }

        let converted = ConversionEngine.convert(word, direction: .auto)
        guard converted != word else {
            AppLog.line("option: convert noop for «\(word)»")
            return
        }
        // Don't skip the next auto word — that felt like Option "ate" the following fix.
        skipNextWord = false
        AppLog.line("option convert «\(word)» -> «\(converted)»")
        performReplacement(
            original: word,
            converted: converted,
            deleteCount: deleteCount,
            suffix: suffix,
            manual: true
        )
    }

    private func performReplacement(
        original: String,
        converted: String,
        deleteCount: Int,
        suffix: String,
        manual: Bool
    ) {
        guard !isConverting else { return }
        isConverting = true
        defer { isConverting = false }

        let toRussian = ConversionEngine.dominantScript(original) == .latin
            || ConversionEngine.dominantScript(converted) == .cyrillic

        undo.remember(ConversionSnapshot(
            original: original,
            converted: converted,
            switchedToRussian: toRussian
        ))

        if toRussian {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
            soundPlayer.play(manual ? .switchToRussian : .autoConvert)
        } else {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
            soundPlayer.play(manual ? .switchToEnglish : .autoConvert)
        }

        usleep(20_000)
        EventSynth.replaceCharacters(deleteCount: deleteCount, with: converted + suffix)
        buffer.clear()
        onStatusChange?(manual ? "manual:\(converted)" : "auto:\(converted)")
    }

    private func convertSelectionIfAny() {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        EventSynth.isSynthesizing = true
        EventSynth.postKey(keyCode: 8, keyDown: true, flags: .maskCommand)
        EventSynth.postKey(keyCode: 8, keyDown: false, flags: .maskCommand)
        usleep(50_000)
        EventSynth.isSynthesizing = false

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

        let toRussian = ConversionEngine.dominantScript(selected) == .latin
        if toRussian {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        } else {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        }

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        EventSynth.isSynthesizing = true
        EventSynth.postKey(keyCode: 9, keyDown: true, flags: .maskCommand)
        EventSynth.postKey(keyCode: 9, keyDown: false, flags: .maskCommand)
        EventSynth.isSynthesizing = false
        soundPlayer.play(.selectionConvert)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    func undoLastConversion() {
        guard let last = undo.last, !isConverting else { return }
        EventSynth.replaceCharacters(deleteCount: last.converted.count, with: last.original)
        if last.switchedToRussian {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        } else {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        }
        soundPlayer.play(.undo)
        undo.learnNever(last.original)
        checker = LayoutChecker(
            validator: SystemWordValidator(),
            neverConvert: undo.learnedNever,
            userRules: settings.userRules
        )
        undo.clearLast()
    }

    func changeCaseOfBufferOrSelection() {
        let word = buffer.stringValue
        if !word.isEmpty {
            let toggled = ConversionEngine.toggleCase(word)
            EventSynth.replaceCharacters(deleteCount: word.count, with: toggled)
            buffer.clear()
            return
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
        conversionGeneration += 1

        if let saved = appLayouts[bundle], !saved.isEmpty {
            _ = inputSources.select(sourceID: saved)
        }
    }
}
