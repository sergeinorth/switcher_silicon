import AppKit
import Engine
import Platform

final class LayoutOrchestrator: EventTapDelegate, @unchecked Sendable {
    private let inputSources = InputSourceManager()
    private let eventTap = EventTap()
    private var soundPlayer: SoundPlayer
    private var settings: AppSettings
    private var checker: LayoutChecker
    private var spellFixer: SpellFixer
    private var buffer = KeyStrokeBuffer()
    private var undo = UndoState()
    private var skipNextWord = false
    private var appLayouts: [String: String] = [:]
    private var lastFrontBundle: String?
    /// Cached so Space does not query NSWorkspace on every key.
    private var cachedFrontBundleID: String?
    private var isConverting = false
    private var lastBufferedWord = ""
    /// Word completed by Space; used only if there is no toggleable snapshot yet.
    private var pendingFinishedWord: String?
    private var pendingFinishedAt: CFAbsoluteTime = 0
    /// Typo candidate for Option+Shift teach (set when a word finishes without layout convert).
    private var teachFromWord: String?
    private var teachFromAt: CFAbsoluteTime = 0
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
        /// Cursor still on the word (no trailing space in field) — Option+Delete once.
        var useWordDelete: Bool
        /// Space already in the field (deferred spell path).
        var trailingSpaceInField: Bool
    }

    var onStatusChange: ((String) -> Void)?
    var isTapActive: Bool { eventTap.isEnabled }

    init(settings: AppSettings) {
        self.settings = settings
        self.soundPlayer = SoundPlayer(settings: settings)
        self.spellFixer = SpellFixer(
            ignoredWords: settings.ignoredWordSet,
            replacements: settings.spellReplacements
        )
        // Bundled dictionary only — NSSpellChecker is too slow on the Space hot path.
        self.checker = LayoutChecker(
            validator: SeedWordValidator(),
            neverConvert: settings.ignoredWordSet,
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

    /// User flipped layout via menu bar / Caps — keep per-app memory in sync so we do not yank it back.
    func noteExternalLayoutChange() {
        guard !isConverting, !EventSynth.isSynthesizing else { return }
        guard let bundle = cachedFrontBundleID ?? FrontmostApp.bundleID else { return }
        if bundle == Bundle.main.bundleIdentifier { return }
        appLayouts[bundle] = inputSources.currentSourceID
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
        Ignored words: \(settings.ignoredWords.sorted().joined(separator: ", "))
        Spell fixes: \(settings.spellReplacements.keys.sorted().joined(separator: ", "))
        Teach from: «\(teachFromWord ?? "")»
        Log: ~/Library/Logs/SwitcherSilicon.log

        \(hint)
        """
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        soundPlayer.settings = settings
        rebuildDetectors()
        SettingsStore.save(settings)
    }

    private func rebuildDetectors() {
        let never = settings.ignoredWordSet.union(undo.learnedNever)
        spellFixer = SpellFixer(ignoredWords: never, replacements: settings.spellReplacements)
        checker = LayoutChecker(
            validator: SeedWordValidator(),
            neverConvert: never,
            userRules: settings.userRules
        )
    }

    /// Persist a word so layout/spell leave it alone. Triggered by undoing an auto-fix (Option / ⌘⌥Z).
    func rememberIgnoredWord(_ word: String) {
        let cleaned = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0 == "-" || $0 == "'" }
        guard cleaned.count >= 2 else { return }
        guard !settings.ignoredWordSet.contains(cleaned) else { return }
        settings.ignoredWords.append(cleaned)
        undo.learnNever(cleaned)
        rebuildDetectors()
        SettingsStore.save(settings)
        AppLog.line("ignore word «\(cleaned)»")
        onStatusChange?("ignore:\(cleaned)")
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

        if WordDetector.isNavigation(keyCode) {
            // Cursor left the word — stale Option toggle/pending would hit the wrong place.
            invalidateTypingContext()
            return Unmanaged.passUnretained(event)
        }

        let busy = isConverting || EventSynth.isSynthesizing

        // Auto-convert ONLY on Space / Tab / Enter (not on , . ; which are RU letters).
        if WordDetector.isSeparatorKeyCode(keyCode) {
            if busy {
                // Keep the word for Option / next attempt — clearing here ate auto-convert.
                if !buffer.isEmpty {
                    pendingFinishedWord = buffer.stringValue
                    lastBufferedWord = buffer.stringValue
                    buffer.clear()
                }
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
            pendingFinishedAt = 0
            undo.clearLast()
            buffer.append(KeyStroke(characters: glyph, keyCode: keyCode))
            lastBufferedWord = buffer.stringValue
        } else if shouldBreakWord(keyCode: keyCode, characters: characters) {
            // Digits / @ / etc. end the token — otherwise Option converts a glued franken-buffer.
            invalidateTypingContext()
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
        if isConverting || EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            AppLog.line("option ignored: synth/convert")
            return
        }
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

    func eventTapDidDetectOptionShiftTap() {
        guard settings.useOptionTrigger else { return }
        if isConverting || EventSynth.isSynthesizing || CFAbsoluteTimeGetCurrent() < EventSynth.ignoreOptionUntil {
            AppLog.line("option+shift ignored: synth/convert")
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastOptionAt < 0.20 {
            AppLog.line("option+shift debounced")
            return
        }
        lastOptionAt = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.handleTeachReplacement()
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
        // KeyCodeMap includes digits/@ — only keep layout-ambiguous word glyphs.
        guard let mapped = KeyCodeMap.usCharacter(keyCode: keyCode, shift: shift),
              mapped.count == 1,
              let ch = mapped.first,
              isBufferableGlyph(ch)
        else {
            return nil
        }
        return mapped
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

    /// Printable key that is not part of a layout-word (digit, @, …) — ends the current token.
    private func shouldBreakWord(keyCode: UInt16, characters: String) -> Bool {
        if let ch = characters.first, characters.count == 1 {
            if ch.isLetter || isBufferableGlyph(ch) { return false }
            if ch.isWhitespace || ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                return false
            }
            return true
        }
        if characters.isEmpty, let mapped = KeyCodeMap.usCharacter(keyCode: keyCode, shift: false) {
            guard let ch = mapped.first, mapped.count == 1 else { return false }
            return !isBufferableGlyph(ch)
        }
        return false
    }

    private func invalidateTypingContext() {
        buffer.clear()
        lastBufferedWord = ""
        pendingFinishedWord = nil
        pendingFinishedAt = 0
        // Keep teachFromWord — user may click away briefly while fixing a typo.
        undo.clearLast()
    }

    private func normalizeTeachWord(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0 == "-" || $0 == "'" }
    }

    private func noteTeachFrom(_ word: String) {
        let cleaned = normalizeTeachWord(word)
        guard cleaned.count >= 2 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // Within the teach window, a *different* finished word is the corrected form — keep typo.
        if let from = teachFromWord,
           now - teachFromAt < 45,
           cleaned.lowercased() != from.lowercased()
        {
            return
        }
        teachFromWord = cleaned
        teachFromAt = now
    }

    private func clearTeachFrom() {
        teachFromWord = nil
        teachFromAt = 0
    }

    private func applySimpleCase(of original: String, to suggestion: String) -> String {
        if let first = original.first, first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    private func taughtReplacement(for word: String) -> String? {
        let cleaned = normalizeTeachWord(word)
        guard cleaned.count >= 2 else { return nil }
        let lower = cleaned.lowercased()
        guard let to = settings.spellReplacements[lower], to.lowercased() != lower else {
            return nil
        }
        return applySimpleCase(of: cleaned, to: to)
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
        pendingFinishedAt = CFAbsoluteTimeGetCurrent()

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
            // Silent — logging every short/empty Space was still work on the tap path.
            return false
        }
        // Reliable replace only on Space.
        guard separatorKeyCode == 49 else { return false }

        if settings.isAutocorrectionActive {
            let check = checker.check(word)
            lastCheckResult = "\(check) for «\(word)»"
            // No AppLog here — keeps Space snappy when no convert.
            if check == .incorrect {
                let converted = ConversionEngine.convert(word, direction: .auto)
                if converted != word {
                    pendingFinishedWord = nil
                    pendingFinishedAt = 0
                    clearTeachFrom()
                    enqueueReplacement(
                        original: word,
                        converted: converted,
                        deleteCount: keystrokes, // space not typed yet
                        suffix: " ",
                        automatic: true,
                        switchLayout: true,
                        immediate: true,
                        useWordDelete: true
                    )
                    return true
                }
            }
        }

        // User-taught fixes: sync on Space (even if general spell heuristics are off).
        if let taught = taughtReplacement(for: word) {
            pendingFinishedWord = nil
            pendingFinishedAt = 0
            clearTeachFrom()
            enqueueReplacement(
                original: word,
                converted: taught,
                deleteCount: keystrokes,
                suffix: " ",
                automatic: true,
                switchLayout: false,
                immediate: true,
                useWordDelete: true
            )
            return true
        }

        noteTeachFrom(word)

        // Spell AFTER Space, off the main run-loop — NSSpellChecker must not block the key.
        if settings.isSpellAutocorrectActive {
            let spellWord = word.filter { $0.isLetter || $0 == "-" || $0 == "'" }
            let strokes = keystrokes
            let expected = word
            let startedAt = pendingFinishedAt
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                guard let fixed = self.spellFixer.suggestion(for: spellWord), fixed != spellWord else {
                    return
                }
                DispatchQueue.main.async {
                    // User kept typing / clicked away — word-delete would leave the typo and append the fix.
                    guard self.pendingFinishedWord == expected, self.buffer.isEmpty else {
                        AppLog.line("spell skip «\(spellWord)»: context moved")
                        return
                    }
                    guard CFAbsoluteTimeGetCurrent() - startedAt < 1.25 else {
                        AppLog.line("spell skip «\(spellWord)»: too late")
                        return
                    }
                    AppLog.line("spell «\(spellWord)» -> «\(fixed)» after-space")
                    self.pendingFinishedWord = nil
                    self.pendingFinishedAt = 0
                    self.clearTeachFrom()
                    // Exact backspaces (not Option+Delete) — async lag made word-delete miss the typo.
                    self.enqueueReplacement(
                        original: word,
                        converted: fixed,
                        deleteCount: strokes + 1,
                        suffix: " ",
                        automatic: true,
                        switchLayout: false,
                        immediate: true,
                        useWordDelete: false,
                        trailingSpaceInField: false
                    )
                }
            }
        }
        return false
    }

    /// Option+Shift: remember teachFrom → current word (buffer or last finished).
    private func handleTeachReplacement() {
        let toRaw: String
        if !buffer.stringValue.isEmpty {
            toRaw = buffer.stringValue
        } else if let pending = pendingFinishedWord, !pending.isEmpty {
            toRaw = pending
        } else {
            AppLog.line("teach: nothing to map to")
            soundPlayer.play(.undo)
            return
        }

        let to = normalizeTeachWord(toRaw)
        guard to.count >= 2 else {
            AppLog.line("teach: target too short")
            soundPlayer.play(.undo)
            return
        }

        guard let fromRaw = teachFromWord,
              CFAbsoluteTimeGetCurrent() - teachFromAt < 45
        else {
            AppLog.line("teach: no typo candidate (type typo+Space, fix, then Option+Shift)")
            soundPlayer.play(.undo)
            return
        }
        let from = normalizeTeachWord(fromRaw)
        guard from.count >= 2, from.lowercased() != to.lowercased() else {
            AppLog.line("teach: same word «\(from)»")
            soundPlayer.play(.undo)
            return
        }

        settings.spellReplacements[from.lowercased()] = to
        // If it was ignored, drop ignore so the taught fix can run.
        settings.ignoredWords.removeAll { $0.lowercased() == from.lowercased() }
        rebuildDetectors()
        SettingsStore.save(settings)
        clearTeachFrom()
        AppLog.line("teach «\(from)» -> «\(to)»")
        soundPlayer.play(.selectionConvert)
        onStatusChange?("teach:\(from)→\(to)")
    }

    private func enqueueReplacement(
        original: String,
        converted: String,
        deleteCount: Int,
        suffix: String,
        automatic: Bool,
        switchLayout: Bool,
        immediate: Bool = false,
        useWordDelete: Bool = false,
        trailingSpaceInField: Bool = false
    ) {
        replaceQueue.append(
            ReplaceJob(
                original: original,
                converted: converted,
                deleteCount: deleteCount,
                suffix: suffix,
                automatic: automatic,
                switchLayout: switchLayout,
                immediate: immediate,
                useWordDelete: useWordDelete,
                trailingSpaceInField: trailingSpaceInField
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
                switchLayout: job.switchLayout,
                useWordDelete: job.useWordDelete,
                trailingSpaceInField: job.trailingSpaceInField
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
    /// 2) pending word after Space (before toggle — otherwise old undo eats the tap)
    /// 3) toggle last conversion (fresh only)
    /// 4) selected text (AX; ⌘C only when range proves a selection)
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
            forceConvert(word: word, deleteCount: Array(word).count, suffix: "", afterSpace: false)
            return
        }

        if let finished = pendingFinishedWord, finished.count >= 1 {
            pendingFinishedWord = nil
            undo.clearLast()
            forceConvert(
                word: finished,
                deleteCount: Array(finished).count + 1,
                suffix: " ",
                afterSpace: true
            )
            return
        }

        // Toggle last conversion (fixes "Option only reverts once").
        if let last = undo.last, isFreshSnapshot(last) {
            if last.showingConverted {
                AppLog.line("option toggle → original «\(last.converted)» -> «\(last.original)»")
                applySnapshot(last, showConverted: false)
            } else {
                AppLog.line("option toggle → converted «\(last.original)» -> «\(last.converted)»")
                applySnapshot(last, showConverted: true)
            }
            // Undoing an automatic fix = "don't touch this word again".
            if last.showingConverted, last.wasAutomatic {
                rememberIgnoredWord(last.original)
            }
            return
        }
        if undo.last != nil {
            AppLog.line("option: drop stale undo")
            undo.clearLast()
        }

        if convertSelectionIfAny() {
            return
        }

        AppLog.line("option: nothing to convert")
        soundPlayer.play(.undo)
    }

    private func isFreshSnapshot(_ snap: ConversionSnapshot) -> Bool {
        Date().timeIntervalSince(snap.createdAt) < 45
    }

    private func forceConvert(word: String, deleteCount: Int, suffix: String, afterSpace: Bool) {
        let converted = ConversionEngine.convert(word, direction: .auto)
        guard converted != word else {
            AppLog.line("option: convert noop for «\(word)»")
            soundPlayer.play(.undo)
            return
        }
        skipNextWord = false
        AppLog.line("option convert «\(word)» -> «\(converted)» delete=\(deleteCount) afterSpace=\(afterSpace)")
        enqueueReplacement(
            original: word,
            converted: converted,
            deleteCount: deleteCount,
            suffix: suffix,
            automatic: false,
            switchLayout: true,
            immediate: true,
            useWordDelete: afterSpace,
            trailingSpaceInField: afterSpace
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
                ensureLayout(wantRussian: true, reason: "toggle")
                soundPlayer.play(.switchToRussian)
            } else {
                ensureLayout(wantRussian: false, reason: "toggle")
                soundPlayer.play(.switchToEnglish)
            }
        } else {
            switch ConversionEngine.dominantScript(last.original) {
            case .latin:
                ensureLayout(wantRussian: false, reason: "revert")
            case .cyrillic:
                ensureLayout(wantRussian: true, reason: "revert")
            case .mixed, .other:
                break
            }
            soundPlayer.play(.undo)
        }

        usleep(15_000)
        // Snapshot toggle uses counted deletes — word length is known exactly.
        EventSynth.replaceCharacters(deleteCount: deleteCount, with: text, useWordDelete: false)

        var updated = last
        updated.showingConverted = showConverted
        undo.remember(updated)
        pendingFinishedWord = nil
        pendingFinishedAt = 0
        buffer.clear()
        onStatusChange?(showConverted ? "toggle:\(last.converted)" : "revert:\(last.original)")
    }

    private func performReplacement(
        original: String,
        converted: String,
        deleteCount: Int,
        suffix: String,
        automatic: Bool,
        switchLayout: Bool,
        useWordDelete: Bool = false,
        trailingSpaceInField: Bool = false
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
                    immediate: true,
                    useWordDelete: useWordDelete,
                    trailingSpaceInField: trailingSpaceInField
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
            ensureLayout(wantRussian: toRussian, reason: automatic ? "auto" : "manual")
            soundPlayer.play(
                automatic
                    ? .autoConvert
                    : (toRussian ? .switchToRussian : .switchToEnglish)
            )
            usleep(8_000)
        } else {
            soundPlayer.play(.autoConvert)
        }

        EventSynth.replaceCharacters(
            deleteCount: deleteCount,
            with: converted + suffix,
            useWordDelete: useWordDelete,
            trailingSpaceInField: trailingSpaceInField
        )
        buffer.clear()
        pendingFinishedWord = nil
        AppLog.line("replaced «\(original)» -> «\(converted)» auto=\(automatic) del=\(deleteCount)")
        onStatusChange?(automatic ? "auto:\(converted)" : "manual:\(converted)")
    }

    /// Returns true if a non-empty selection was found and handled.
    @discardableResult
    private func convertSelectionIfAny() -> Bool {
        switch SelectedText.probe() {
        case .empty, .none:
            return false
        case let .text(ax):
            return applySelectionConversion(ax, viaAX: true)
        case .unreadSelection:
            // Only when AX range length > 0 — never speculative ⌘C (old clipboard / whole field).
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
        ensureLayout(wantRussian: toRussian, reason: "selection")

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
        if last.wasAutomatic {
            rememberIgnoredWord(last.original)
        }
    }

    func toggleSpellAutocorrect() {
        settings.isSpellAutocorrectActive.toggle()
        reloadSettings(settings)
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
        let bundle = cachedFrontBundleID ?? FrontmostApp.bundleID
        cachedFrontBundleID = bundle
        guard let bundle else { return false }
        return settings.excludedApps.contains(bundle)
    }

    private func observeAppActivation() {
        cachedFrontBundleID = FrontmostApp.bundleID
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
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundle = app.bundleIdentifier
        else { return }

        // Menu-bar accessory activations must not yank the user's layout.
        if bundle == Bundle.main.bundleIdentifier { return }

        cachedFrontBundleID = bundle
        buffer.clear()
        undo.clearLast()
        pendingFinishedWord = nil

        guard settings.rememberLayoutPerApp else { return }
        // Don't fight an in-flight convert (was restoring stale EN after we flipped to RU).
        guard !isConverting, !EventSynth.isSynthesizing else { return }

        if let previous = lastFrontBundle, previous != Bundle.main.bundleIdentifier {
            appLayouts[previous] = inputSources.currentSourceID
        }
        lastFrontBundle = bundle

        if let saved = appLayouts[bundle], !saved.isEmpty, saved != inputSources.currentSourceID {
            let ok = inputSources.select(sourceID: saved)
            AppLog.line(
                "remember layout \(bundle) → \(saved) ok=\(ok) now=\(inputSources.currentSourceID)"
            )
        }
    }

    /// Flip system layout and remember it for the front app so per-app restore cannot undo us.
    @discardableResult
    private func ensureLayout(wantRussian: Bool, reason: String) -> Bool {
        let before = inputSources.currentSourceID
        let ok: Bool
        if wantRussian {
            ok = inputSources.switchToRussian(preferredID: settings.russianLayoutID)
        } else {
            ok = inputSources.switchToEnglish(preferredID: settings.englishLayoutID)
        }
        // Brief settle only — long verify sleeps blocked the tap and killed the next auto-convert.
        if ok { usleep(8_000) }
        let after = inputSources.currentSourceID
        let matched = wantRussian ? inputSources.isCurrentRussian : !inputSources.isCurrentRussian
        if !ok || !matched {
            AppLog.line(
                "layout FAIL \(reason) want=\(wantRussian ? "RU" : "EN") before=\(before) after=\(after)"
            )
        } else if before != after {
            AppLog.line("layout \(reason) \(before) → \(after)")
        }
        // Remember the *intended* layout even if TIS lags — stops per-app restore from snapping back.
        if let bundle = cachedFrontBundleID ?? FrontmostApp.bundleID,
           bundle != Bundle.main.bundleIdentifier
        {
            let intended = wantRussian
                ? (settings.russianLayoutID.isEmpty ? after : settings.russianLayoutID)
                : (settings.englishLayoutID.isEmpty ? after : settings.englishLayoutID)
            appLayouts[bundle] = intended.isEmpty ? after : intended
            cachedFrontBundleID = bundle
        }
        return ok || matched
    }

    /// Gunzip + build ~2M-word Sets off the typing path (first Space used to hitch).
    func warmDictionaries() {
        DispatchQueue.global(qos: .utility).async {
            _ = BundledDictionary.russianCount
            _ = BundledDictionary.englishCount
            _ = BundledDictionary.spellAcceptRussianCount
            AppLog.line(
                "dicts warm RU=\(BundledDictionary.russianCount) EN=\(BundledDictionary.englishCount)"
            )
        }
    }
}
