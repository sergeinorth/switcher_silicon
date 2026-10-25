# Switcher Silicon

**[English](README.md)** · **[Русский](README.ru.md)**

Переключатель раскладки в духе Punto Switcher для **macOS на Apple Silicon** (arm64).

Исправляет текст, набранный не в той раскладке (EN ↔ RU), плюс опциональные опечатки. Без телеметрии и без сети в ядре.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2014+%20arm64-black)](README.md#requirements)

## Скачать

**[v0.1.5 — SwitcherSilicon-0.1.5-macos-arm64.zip](https://github.com/sergeinorth/switcher_silicon/releases/latest)**

Распаковать, перенести `SwitcherSilicon.app` в `/Applications`, выдать Универсальный доступ и Мониторинг ввода. Если Gatekeeper ругается — см. notes релиза.

## Возможности

- **Автоконвертация** — после пробела чинит слово (`ghbdtn` → `привет`) и меняет раскладку
- **Option** — принудительно конвертирует текущее слово; иначе переключает последнюю конвертацию туда-сюда
- **Выделение + Option** — конвертирует весь selected text
- **Автоопечатки** (по умолчанию выкл) — осторожные правки вроде `превет` → `привет`
- **Язык интерфейса** — Русский / English в меню
- **Отмена** — из меню или ⌘⌥Z; Option тоже откатывает/возвращает
- **Звуки** — вкл/выкл и выбор системного звука на событие
- **Память раскладки по приложениям** и **исключение текущего приложения**
- **Диагностика**, ссылки в настройки прав
- В меню-баре **РУ** / **EN** (или `!`, если tap не активен)

## Требования

- macOS 14+
- Apple Silicon (arm64)
- Xcode Command Line Tools
- **Универсальный доступ** + **Мониторинг ввода** для `/Applications/SwitcherSilicon.app`

Выключи RuSwitcher / Punto / Caramba — два перехватчика клавиатуры мешают друг другу.

## Сборка

```sh
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh
```

Отладка:

```sh
swift run Smoke
./Scripts/package-app.sh
```

### Первый запуск

1. Системные настройки → Конфиденциальность и безопасность → **Универсальный доступ**  
2. Там же → **Мониторинг ввода**  
3. Gatekeeper: правый клик → Открыть, или `xattr -cr /Applications/SwitcherSilicon.app`

## Меню

| Пункт | Смысл |
|------|--------|
| Автоконвертация | Правка раскладки по пробелу |
| Автоопечатки | Опциональный spell |
| Звуки / Выбор звуков | Общий выключатель и звуки по событиям |
| Язык интерфейса | Русский или English |
| Отменить последнюю конвертацию | ⌘⌥Z |
| Исключить текущее приложение | Не трогать это приложение |

Лог: `~/Library/Logs/SwitcherSilicon.log`

## Словари

См. `Sources/Engine/Resources/Dictionaries/NOTICE.md`. Обновить:

```sh
./Scripts/fetch-dictionaries.sh
./Scripts/package-app.sh
```

## Участие

Любой может сделать **fork** и открыть **Pull Request**. Подробности: [CONTRIBUTING.ru.md](CONTRIBUTING.ru.md).

## Лицензия

[MIT](LICENSE). Лицензии словарей — в `NOTICE.md`.
