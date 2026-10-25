import AppKit
import Engine
import Platform

final class LayoutOrchestrator: EventTapDelegate, @unchecked Sendable {
    private let inputSources = InputSourceManager()
    private let eventTap = EventTap()
    private var soundPlayer: SoundPlayer
    private var settings: AppSettings
    private var checker: LayoutChecker
    private let spellFixer = SpellFixer()
    private var buffer = KeyStrokeBuffer()
    private var undo = UndoState()
    private var skipNextWord = false
    private var appLayouts: [String: String] = [:]
    private var lastFrontBundle: String?
    private var isConverting = false
    private var lastBufferedWord = ""
    /// Word completed by Space; used only if there is no toggleable snapshot yet.
    private var pendingFinishedWord: String?
    private var lastCheckResult = "—"
    private var keyEventCount = 0
    private var lastOptionAt: CFAbsoluteTime = 0
    private var replaceQueue: [ReplaceJob] = []

    private struct ReplaceJob {
        var original: String
        var converted: String
        var deleteCount: Int
        var suffix: String
        var automatic: Bool
        var switchLayout: Bool
        /// Space was swallowed — replace ASAP (no wait for key commit).
        var immediate: Bool
    }

    var onStatusChange: ((String) -> Void)?
    var isTapActive: Bool { eventTap.isEnabled }

    init(settings: AppSettings) {
        self.settings = settings
        self.soundPlayer = SoundPlayer(settings: settings)
        // Bundled dictionary only — NSSpellChecker is too slow on the Space hot path.
        self.checker = LayoutChecker(
            validator: SeedWordValidator(),
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
        let hint = L10n.t(.diagHint, settings.uiLanguage)
        return """
        \(AccessibilityPermission.diagnosticsLine)
        Event tap: \(eventTap.isEnabled ? "ok" : "NO")
        Autocorrect: \(settings.isAutocorrectionActive ? "on" : "off")
        Spell: \(settings.isSpellAutocorrectActive ? "on" : "off")
        UI: \(settings.uiLanguage.rawValue)
        Layout: \(inputSources.currentSourceID)
        Front app: \(FrontmostApp.bundleID ?? "?")
        Keys seen: \(keyEventCount)
        Last buffer: «\(lastBufferedWord)»
        Pending finished: «\(pendingFinishedWord ?? "")»
        Last check: \(lastCheckResult)
        Excluded: \(settings.excludedApps.joined(separator: ", "))
        Log: ~/Library/Logs/SwitcherSilicon.log

        \(hint)
        """
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        soundPlayer.settings = settings
        checker = LayoutChecker(
            validator: SeedWordValidator(),
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
                buffer.clear()
                return Unmanaged.passUnretained(event)
            }
            // Swallow Space when we convert: avoid race (first letter left behind).
            if handleSeparatorKey(keyCode) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if flags.contains(.maskAlternate) && characters.isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let shift = flags.contains(.maskShift)
        if let glyph = resolvedGlyph(characters: characters, keyCode: keyCode, shift: shift) {
            // New typing: don't Option-revert an old auto word into the new text.
            pendingFinishedWord = nil
            undo.clearLast()
            buffer.append(KeyStroke(characters: glyph, keyCode: keyCode))
            lastBufferedWord = buffer.stringValue
        }

        return Unmanaged.passUnretained(event)
    }

    func eventTap(didReceiveKeyUp keyCode: UInt16, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Space keyDown was swallowed for convert — drop matching keyUp too.
        if keyCode == 49, isConverting || EventSynth.isSynthesizing {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    func eventTapDidReceiveFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        Unmanaged.passUnretained(event)
    }

    func eventTapDidDetectOptionTap() {
        guard settings.useOptionTrigger else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // Debounce: repeated Option taps were eating the buffer then pasting an old clipboard word.
        if now - lastOptionAt < 0.20 {
            AppLog.line("option debounced")
            return
        }
        lastOptionAt = now
        AppLog.line(
            "option tap buffer=«\(buffer.stringValue)» pending=«\(pendingFinishedWord ?? "")» undo=\(undo.last.map { "\($0.showingConverted ? "shown" : "reverted"):\($0.converted)" } ?? "nil")"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.handleOptionTap()
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

    /// Returns `true` when Space must be swallowed (we type converted word + space ourselves).
    @discardableResult
    private func handleSeparatorKey(_ separatorKeyCode: UInt16) -> Bool {
        let keystrokes = buffer.count
        let word = buffer.stringValue
        buffer.clear()
        lastBufferedWord = word
        undo.clearLast()
        pendingFinishedWord = word

        if skipNextWord {
            skipNextWord = false
            AppLog.line("skip next word after manual")
            return false
        }
        if settings.noAutoconvertAfterTabOrEnter,
           separatorKeyCode == 48 || separatorKeyCode == 36 || separatorKeyCode == 76
        {
            return false
        }
        guard keystrokes >= 2, word.count >= 2 else {
            AppLog.line("word too short «\(word)»")
            return false
        }
        // Reliable replace only on Space.
        guard separatorKeyCode == 49 else { return false }

        if settings.isAutocorrectionActive {
            let check = checker.check(word)
            lastCheckResult = "\(check) for «\(word)»"
            AppLog.line("check \(lastCheckResult)")
            if check == .incorrect {
                let converted = ConversionEngine.convert(word, direction: .auto)
                if converted != word {
                    AppLog.line("schedule layout «\(word)» -> «\(converted)» swallow-space")
                    pendingFinishedWord = nil
                    enqueueReplacement(
                        original: word,
                        converted: converted,
                        deleteCount: keystrokes, // space not typed yet
                        suffix: " ",
                        automatic: true,
                        switchLayout: true,
                        immediate: true
                    )
                    return true
                }
            }
        }

        if settings.isSpellAutocorrectActive {
            let spellWord = word.filter { $0.isLetter || $0 == "-" || $0 == "'" }
            if let fixed = spellFixer.suggestion(for: spellWord), fixed != spellWord {
                AppLog.line("spell «\(spellWord)» -> «\(fixed)» swallow-space")
                pendingFinishedWord = nil
                enqueueReplacement(
                    original: word,
                    converted: fixed,
                    deleteCount: keystrokes,
                    suffix: " ",
                    automatic: true,
                    switchLayout: false,
                    immediate: true
                )
                return true
            }
        }
        return false
    }

    private func enqueueReplacement(
        original: String,
        converted: String,
        deleteCount: Int,
        suffix: String,
        automatic: Bool,
        switchLayout: Bool,
        immediate: Bool = false
    ) {
        replaceQueue.append(
            ReplaceJob(
                original: original,
                converted: converted,
                deleteCount: deleteCount,
                suffix: suffix,
                automatic: automatic,
                switchLayout: switchLayout,
                immediate: immediate
            )
        )
        pumpReplaceQueue()
    }

    private func pumpReplaceQueue() {
        guard !isConverting, !replaceQueue.isEmpty else { return }
        let job = replaceQueue.removeFirst()
        let delay = job.immediate ? 0.0 : 0.03
        let run = { [weak self] in
            guard let self else { return }
            self.performReplacement(
                original: job.original,
                converted: job.converted,
                deleteCount: job.deleteCount,
                suffix: job.suffix,
                automatic: job.automatic,
                switchLayout: job.switchLayout
            )
            self.pumpReplaceQueue()
        }
        if delay <= 0 {
            DispatchQueue.main.async(execute: run)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
        }
    }

    /// Option:
    /// 1) typed buffer → force convert
    /// 2) selected text (AX, else ⌘C probe) → flip whole selection
    /// 3) toggle last conversion
    /// 4) pending word after Space
    private func handleOptionTap() {
        guard !isConverting else {
            AppLog.line("option ignored: busy converting")
            return
        }

        let fromBuffer = buffer.stringValue

        if fromBuffer.count >= 1 {
            let word = fromBuffer
            buffer.clear()
            pendingFinishedWord = nil
            forceConvert(word: word, deleteCount: Array(word).count, suffix: "")
            return
        }

        if convertSelectionIfAny() {
            return
        }

        // Toggle last conversion (fixes "Option only reverts once").
        if let last = undo.last {
            if last.showingConverted {
                AppLog.line("option toggle → original «\(last.converted)» -> «\(last.original)»")
                applySnapshot(last, showConverted: false)
            } else {
                AppLog.line("option toggle → converted «\(last.original)» -> «\(last.converted)»")
                applySnapshot(last, showConverted: true)
            }
            return
        }

        if let finished = pendingFinishedWord, finished.count >= 1 {
            pendingFinishedWord = nil
            forceConvert(word: finished, deleteCount: Array(finished).count + 1, suffix: " ")
            return
        }

        AppLog.line("option: nothing to convert")
        soundPlayer.play(.undo)
    }

    private func forceConvert(word: String, deleteCount: Int, suffix: String) {
        let converted = ConversionEngine.convert(word, direction: .auto)
        guard converted != word else {
            AppLog.line("option: convert noop for «\(word)»")
            soundPlayer.play(.undo)
            return
        }
        skipNextWord = false
        AppLog.line("option convert «\(word)» -> «\(converted)» delete=\(deleteCount)")
        enqueueReplacement(
            original: word,
            converted: converted,
            deleteCount: deleteCount,
            suffix: suffix,
            automatic: false,
            switchLayout: true
        )
    }

    private func applySnapshot(_ last: ConversionSnapshot, showConverted: Bool) {
        isConverting = true
        defer {
            isConverting = false
            pumpReplaceQueue()
        }

        let space = last.hadTrailingSpace
        let from = showConverted ? last.original : last.converted
        let to = showConverted ? last.converted : last.original
        let deleteCount = Array(from).count + (space ? 1 : 0)
        let text = to + (space ? " " : "")

        if showConverted {
            let toRussian = ConversionEngine.dominantScript(last.original) == .latin
                || ConversionEngine.dominantScript(last.converted) == .cyrillic
            if toRussian {
                _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
                soundPlayer.play(.switchToRussian)
            } else {
                _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
                soundPlayer.play(.switchToEnglish)
            }
        } else {
            switch ConversionEngine.dominantScript(last.original) {
            case .latin:
                _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
            case .cyrillic:
                _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
            case .mixed, .other:
                break
            }
            soundPlayer.play(.undo)
        }

        usleep(15_000)
        EventSynth.replaceCharacters(deleteCount: deleteCount, with: text)

        var updated = last
        updated.showingConverted = showConverted
        undo.remember(updated)
        pendingFinishedWord = nil
        buffer.clear()
        onStatusChange?(showConverted ? "toggle:\(last.converted)" : "revert:\(last.original)")
    }

    private func performReplacement(
        original: String,
        converted: String,
        deleteCount: Int,
        suffix: String,
        automatic: Bool,
        switchLayout: Bool
    ) {
        guard !isConverting else {
            replaceQueue.insert(
                ReplaceJob(
                    original: original,
                    converted: converted,
                    deleteCount: deleteCount,
                    suffix: suffix,
                    automatic: automatic,
                    switchLayout: switchLayout,
                    immediate: true
                ),
                at: 0
            )
            return
        }
        isConverting = true
        defer { isConverting = false }

        let toRussian = ConversionEngine.dominantScript(original) == .latin
            || ConversionEngine.dominantScript(converted) == .cyrillic
        let hadSpace = suffix == " "

        undo.remember(ConversionSnapshot(
            original: original,
            converted: converted,
            switchedToRussian: switchLayout && toRussian,
            hadTrailingSpace: hadSpace,
            wasAutomatic: automatic,
            showingConverted: true
        ))

        if switchLayout {
            if toRussian {
                _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
                soundPlayer.play(automatic ? .autoConvert : .switchToRussian)
            } else {
                _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
                soundPlayer.play(automatic ? .autoConvert : .switchToEnglish)
            }
            usleep(8_000)
        } else {
            soundPlayer.play(.autoConvert)
        }

        EventSynth.replaceCharacters(deleteCount: deleteCount, with: converted + suffix)
        buffer.clear()
        pendingFinishedWord = nil
        AppLog.line("replaced «\(original)» -> «\(converted)» auto=\(automatic) del=\(deleteCount)")
        onStatusChange?(automatic ? "auto:\(converted)" : "manual:\(converted)")
    }

    /// Returns true if a non-empty selection was found and handled.
    @discardableResult
    private func convertSelectionIfAny() -> Bool {
        switch SelectedText.probe() {
        case .empty:
            return false
        case let .text(ax):
            return applySelectionConversion(ax, viaAX: true)
        case .unknown:
            // Fallback for apps without AX selected-text (Chrome, some Electron).
            return convertSelectionViaClipboard()
        }
    }

    private func convertSelectionViaClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        let changeAfterClear = pasteboard.changeCount

        EventSynth.isSynthesizing = true
        EventSynth.postKey(keyCode: 8, keyDown: true, flags: .maskCommand) // ⌘C
        EventSynth.postKey(keyCode: 8, keyDown: false, flags: .maskCommand)
        usleep(90_000)
        EventSynth.isSynthesizing = false

        guard pasteboard.changeCount != changeAfterClear,
              let selected = pasteboard.string(forType: .string),
              !selected.isEmpty
        else {
            restorePasteboard(previous)
            return false
        }

        let ok = applySelectionConversion(selected, viaAX: false, previousClipboard: previous)
        if !ok {
            restorePasteboard(previous)
        }
        return ok
    }

    private func applySelectionConversion(
        _ selected: String,
        viaAX: Bool,
        previousClipboard: String? = nil
    ) -> Bool {
        guard selected.count <= 8_000 else {
            AppLog.line("option selection too large (\(selected.count))")
            return true
        }

        let converted = ConversionEngine.flipLayout(selected)
        guard converted != selected else {
            AppLog.line("option selection noop «\(preview(selected))»")
            soundPlayer.play(.undo)
            return true
        }

        isConverting = true
        defer { isConverting = false }

        let toRussian = ConversionEngine.dominantScript(selected) == .latin
            || ConversionEngine.dominantScript(converted) == .cyrillic
        if toRussian {
            _ = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        } else {
            _ = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        }

        var replaced = false
        if viaAX {
            replaced = SelectedText.replaceAX(converted)
        }
        if !replaced {
            let pasteboard = NSPasteboard.general
            if previousClipboard == nil {
                // AX path fell back to paste — preserve clipboard.
                let previous = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                pasteboard.setString(converted, forType: .string)
                EventSynth.isSynthesizing = true
                EventSynth.postKey(keyCode: 9, keyDown: true, flags: .maskCommand)
                EventSynth.postKey(keyCode: 9, keyDown: false, flags: .maskCommand)
                usleep(40_000)
                EventSynth.isSynthesizing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [previous] in
                    self.restorePasteboard(previous)
                }
            } else {
                pasteboard.clearContents()
                pasteboard.setString(converted, forType: .string)
                usleep(15_000)
                EventSynth.isSynthesizing = true
                EventSynth.postKey(keyCode: 9, keyDown: true, flags: .maskCommand)
                EventSynth.postKey(keyCode: 9, keyDown: false, flags: .maskCommand)
                usleep(40_000)
                EventSynth.isSynthesizing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [previousClipboard] in
                    self.restorePasteboard(previousClipboard)
                }
            }
        }

        undo.remember(ConversionSnapshot(
            original: selected,
            converted: converted,
            switchedToRussian: toRussian,
            hadTrailingSpace: false,
            wasAutomatic: false,
            showingConverted: true
        ))
        buffer.clear()
        pendingFinishedWord = nil
        soundPlayer.play(.selectionConvert)
        AppLog.line(
            "option selection(\(viaAX ? "ax" : "clip")) «\(preview(selected))» -> «\(preview(converted))»"
        )
        onStatusChange?("selection:\(preview(converted))")
        return true
    }

    private func restorePasteboard(_ previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }

    private func preview(_ text: String, limit: Int = 40) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    func undoLastConversion() {
        guard let last = undo.last, last.showingConverted, !isConverting else { return }
        applySnapshot(last, showConverted: false)
        undo.learnNever(last.original)
        checker = LayoutChecker(
            validator: SeedWordValidator(),
            neverConvert: undo.learnedNever,
            userRules: settings.userRules
        )
    }

    func toggleSpellAutocorrect() {
        settings.isSpellAutocorrectActive.toggle()
        reloadSettings(settings)
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
        undo.clearLast()
        pendingFinishedWord = nil

        if let saved = appLayouts[bundle], !saved.isEmpty {
            _ = inputSources.select(sourceID: saved)
        }
    }
}
