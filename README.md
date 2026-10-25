# Switcher Silicon

Punto Switcher–style layout switcher for **macOS on Apple Silicon** (arm64).

Converts text typed in the wrong keyboard layout (EN ↔ RU), with optional typo fixes. No telemetry, no network for core features.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2014+%20arm64-black)](#requirements)

## Download

**[v0.1.0 — SwitcherSilicon-0.1.0-macos-arm64.zip](https://github.com/sergeinorth/switcher_silicon/releases/latest)**

Unpack, move `SwitcherSilicon.app` to `/Applications`, allow Accessibility + Input Monitoring. See release notes for Gatekeeper tips.

## Features

- **Auto layout convert** — after Space, flips a mistyped word (`ghbdtn` → `привет`) and switches input source
- **Option** — force-convert the current word; if nothing is being typed, toggle the last conversion (undo ↔ redo)
- **Selection convert** — select any text, press Option: whole selection flips EN ↔ RU (Accessibility, clipboard fallback)
- **Spell autocorrect** (off by default) — conservative fixes like `превет` → `привет` using bundled open dictionaries
- **Undo** — menu or ⌘⌥Z; Option also reverts/reapplies the last auto or manual convert
- **Sounds** — on/off plus per-event system sound picker (switch RU/EN, auto, undo, selection)
- **Per-app layout memory** and **exclude current app**
- **Change case** of the buffered word
- **Diagnostics** and shortcuts to open Accessibility / Input Monitoring settings
- Menu bar title shows **РУ** / **EN** (or `!` if the event tap is down)

## Requirements

- macOS 14+
- Apple Silicon (arm64)
- Xcode Command Line Tools (full Xcode only for `swift test`)
- **Accessibility** + **Input Monitoring** for `/Applications/SwitcherSilicon.app`

Turn off RuSwitcher / Punto / Caramba while using this app so only one keyboard tap is active.

## Install (build)

```sh
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh
# installs to /Applications/SwitcherSilicon.app and signs with a local cert if present
```

Debug:

```sh
swift run Smoke          # Engine + dictionary smoke checks
./Scripts/package-app.sh
```

### First launch

1. System Settings → Privacy & Security → **Accessibility** — enable Switcher Silicon  
2. Same section → **Input Monitoring** — enable Switcher Silicon  
3. If Gatekeeper blocks: right-click → Open, or `xattr -cr /Applications/SwitcherSilicon.app`

## Menu

| Item | Meaning |
|------|---------|
| Автоконвертация | Layout auto-fix on Space |
| Автоопечатки | Optional typo fix (frequency dictionary) |
| Звуки / Выбор звуков | Master switch + per-event sounds |
| Отменить последнюю конвертацию | Undo last replace (⌘⌥Z) |
| Сменить регистр | Toggle case of buffered word |
| Диагностика… | Permissions, tap status, log path |
| Исключить текущее приложение | Skip auto/Option in frontmost app |

Log: `~/Library/Logs/SwitcherSilicon.log`

## Dictionaries

Bundled under `Sources/Engine/Resources/Dictionaries/` (see `NOTICE.md`):

| File | Role | Source |
|------|------|--------|
| `ru_words.txt.gz` | ~1.55M RU forms — “is this already a word?” | [danakt/russian-words](https://github.com/danakt/russian-words) (MIT) + hingston |
| `ru_freq.txt.gz` | ~87k — accepted spell *fixes* only | [hingston/russian](https://github.com/hingston/russian) |
| `en_words.txt.gz` | ~370k English | [dwyl/english-words](https://github.com/dwyl/english-words) (Unlicense) |

Refresh from upstream:

```sh
./Scripts/fetch-dictionaries.sh
./Scripts/package-app.sh
```

## Project layout

```
Sources/
  Engine/     conversion, buffer, checkers, dictionaries
  Platform/   event tap, synth, sounds, spell fixer, AX selection
  App/        menu bar app, orchestrator, permissions
Scripts/      package-app.sh, fetch-dictionaries.sh
```

## Contributing

Public repo: anyone can **fork** and open a **Pull Request**. You review and merge (or not). Issues are fine for bugs and ideas.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Dictionary licenses are listed in `Sources/Engine/Resources/Dictionaries/NOTICE.md`.
