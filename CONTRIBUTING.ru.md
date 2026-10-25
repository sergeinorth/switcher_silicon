# Участие в проекте

**[English](CONTRIBUTING.md)** · **[Русский](CONTRIBUTING.ru.md)**

Switcher Silicon открыт для улучшений. Отдельный доступ не нужен.

## Как предложить изменение

1. Сделай **fork** репозитория на GitHub.
2. Создай ветку, внеси правки, прогони `swift run Smoke` и при необходимости `./Scripts/package-app.sh`.
3. Открой **Pull Request** в `main`.

Maintainer смотрит diff и может смержить, попросить правки или закрыть. Issues — для багов и идей.

## Рамки

Только **macOS на Apple Silicon** (arm64). Без телеметрии и сетевых запросов в ядре переключения.

Словари: `./Scripts/fetch-dictionaries.sh`, атрибуция в `Sources/Engine/Resources/Dictionaries/NOTICE.md`.

Строки интерфейса: `Sources/App/L10n.swift` (русский и английский).
