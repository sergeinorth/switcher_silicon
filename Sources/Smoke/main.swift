import Engine
import Foundation
import Platform

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    print("ok: \(message)")
}

expect(ConversionEngine.convert("ghbdtn", direction: .usToRussian) == "привет", "ghbdtn -> привет")
expect(ConversionEngine.convert("руддщ", direction: .russianToUs) == "hello", "руддщ -> hello")
expect(ConversionEngine.convert("ghbdtn", direction: .auto) == "привет", "auto latin")
expect(ConversionEngine.convert("руддщ", direction: .auto) == "hello", "auto cyrillic")
expect(ConversionEngine.convert("ntcn123", direction: .usToRussian) == "тест123", "ntcn123 -> тест123")
expect(ConversionEngine.convert("test", direction: .usToRussian) == "еуые", "test -> еуые")
expect(ConversionEngine.toggleCase("Привет") == "пРИВЕТ", "toggle case")
expect(ConversionEngine.flipLayout("ghbdtn ,hfn") == "привет брат", "flip selection phrase")
expect(ConversionEngine.flipLayout("привет брат") == "ghbdtn ,hfn", "flip selection back")
expect(ConversionEngine.flipLayout("Ghbdtn!") == "Привет!", "flip keeps punctuation")
expect(EditDistance.between("превет", "привет", limit: 1) == 1, "edit distance превет")
expect(EditDistance.between("ощибок", "ошибок", limit: 1) == 1, "edit distance ощибок")

let spell = SpellFixer()
expect(spell.suggestion(for: "превет") == "привет", "spell превет")
expect(spell.suggestion(for: "ощибок") == "ошибок", "spell ощибок")
expect(spell.suggestion(for: "привет") == nil, "spell skip known")
expect(spell.suggestion(for: "helllo") == "hello", "spell helllo")
expect(spell.suggestion(for: "автоконвертация") == nil, "spell skip compound junk")
expect(spell.suggestion(for: "прпревет") == nil, "spell skip ambiguous")

let checker = LayoutChecker()
expect(checker.check("ghbdtn") == .incorrect, "checker ghbdtn")
expect(checker.check("руддщ") == .incorrect, "checker руддщ")
expect(checker.check("привет") == .unknown, "checker real russian")
expect(checker.check("hello") == .unknown, "checker real english")

var buffer = KeyStrokeBuffer()
buffer.append(KeyStroke(characters: "g", keyCode: 5))
buffer.append(KeyStroke(characters: "h", keyCode: 4))
expect(buffer.stringValue == "gh", "buffer join")
buffer.deleteBackward()
expect(buffer.stringValue == "g", "buffer backspace")

let settings = AppSettings.default
expect(settings.isAutocorrectionActive, "default auto on")

print("All smoke checks passed.")
