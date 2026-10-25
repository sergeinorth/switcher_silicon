# Switcher Silicon

**[English](README.md)** · **[Русский](README.ru.md)**

Punto Switcher–style layout switcher for **macOS on Apple Silicon** (arm64).

Converts text typed in the wrong keyboard layout (EN ↔ RU), with optional typo fixes. No telemetry, no network for core features.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2014+%20arm64-black)](#requirements)

## Download

**[v0.1.3 — SwitcherSilicon-0.1.3-macos-arm64.zip](https://github.com/sergeinorth/switcher_silicon/releases/latest)**

Unpack, move `SwitcherSilicon.app` to `/Applications`, allow Accessibility + Input Monitoring. See release notes for Gatekeeper tips.

## Features

- **Auto layout convert** — after Space, flips a mistyped word (`ghbdtn` → `привет`) and switches input source
- **Option** — force-convert the current word; if nothing is being typed, toggle the last conversion (undo ↔ redo)
- **Selection convert** — select any text, press Option: whole selection flips EN ↔ RU
- **Spell autocorrect** (off by default) — conservative fixes like `превет` → `привет`
- **UI language** — Russian / English in the menu bar menu
- **Undo** — menu or ⌘⌥Z; Option also reverts/reapplies the last convert
- **Sounds** — on/off plus per-event system sound picker
- **Per-app layout memory** and **exclude current app**
- **Change case**, **diagnostics**, Accessibility / Input Monitoring shortcuts
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
```

Debug:

```sh
swift run Smoke
./Scripts/package-app.sh
```

### First launch

1. System Settings → Privacy & Security → **Accessibility** — enable Switcher Silicon  
2. Same → **Input Monitoring** — enable Switcher Silicon  
3. If Gatekeeper blocks: right-click → Open, or `xattr -cr /Applications/SwitcherSilicon.app`

## Menu

| Item | Meaning |
|------|---------|
| Auto-convert / Автоконвертация | Layout auto-fix on Space |
| Spell fix / Автоопечатки | Optional typo fix |
| Sounds | Master switch + per-event sounds |
| UI language / Язык интерфейса | Russian or English menu |
| Undo last conversion | ⌘⌥Z |
| Exclude current app | Skip auto/Option in frontmost app |

Log: `~/Library/Logs/SwitcherSilicon.log`

## Dictionaries

See `Sources/Engine/Resources/Dictionaries/NOTICE.md`. Refresh:

```sh
./Scripts/fetch-dictionaries.sh
./Scripts/package-app.sh
```

| File | Role |
|------|------|
| `ru_words.txt.gz` | ~1.55M RU forms |
| `ru_freq.txt.gz` | ~87k spell-accept list |
| `en_words.txt.gz` | ~370k English |

## Contributing

Anyone can **fork** and open a **Pull Request**. See [CONTRIBUTING.md](CONTRIBUTING.md) / [CONTRIBUTING.ru.md](CONTRIBUTING.ru.md).

## License

[MIT](LICENSE). Dictionary licenses in `NOTICE.md` under Dictionaries.
