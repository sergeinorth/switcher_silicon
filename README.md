# Switcher Silicon

Замена Punto Switcher для macOS на Apple Silicon (arm64).

- Автоконвертация слова при пробеле / пунктуации
- Option — ручная конвертация последнего слова или выделения
- Undo, звуки, исключения приложений, раскладка на приложение, смена регистра
- Без телеметрии и сети

Требования: macOS 14+, Apple Silicon, Xcode Command Line Tools.

## Сборка

```sh
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh
open build/SwitcherSilicon.app
```

Или в отладке:

```sh
swift build
swift run Smoke          # логика Engine (на CLT без полного Xcode)
./Scripts/package-app.sh
open build/SwitcherSilicon.app
```

Полный `swift test` (XCTest) нужен установленный Xcode, не только Command Line Tools.

## Первый запуск

1. Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
2. Включи `SwitcherSilicon`
3. Если Gatekeeper ругается: правый клик → Открыть, или `xattr -cr build/SwitcherSilicon.app`

Отключи RuSwitcher / Punto, чтобы не было двух перехватчиков клавиатуры.

## Меню

- Автоконвертация вкл/выкл
- Звуки вкл/выкл
- Отменить последнюю конвертацию (⌘⌥Z из меню)
- Сменить регистр
- Исключить текущее приложение

## Лицензия

MIT.
