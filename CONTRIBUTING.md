# Contributing

**[English](CONTRIBUTING.md)** · **[Русский](CONTRIBUTING.ru.md)**

Switcher Silicon is open for improvements. You do not need special access to propose changes.

## How to suggest a change

1. Fork the repository on GitHub.
2. Create a branch, make your changes, run `swift run Smoke` and `./Scripts/package-app.sh` if you touched app code.
3. Open a **Pull Request** against `main`.

The maintainer reviews the PR and can merge, request edits, or close it. Issues are welcome for bugs and feature ideas.

## Scope

This project targets **macOS on Apple Silicon only** (arm64). Keep the app offline: no telemetry, no network calls for core switching.

Dictionary updates: prefer `./Scripts/fetch-dictionaries.sh` and keep attribution in `Sources/Engine/Resources/Dictionaries/NOTICE.md`.

UI strings live in `Sources/App/L10n.swift` (Russian + English).
