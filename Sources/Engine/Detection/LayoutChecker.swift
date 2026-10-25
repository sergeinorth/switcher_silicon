import Foundation

public enum LayoutCheckResult: Equatable, Sendable {
    case unknown
    case incorrect
    case exception
}

/// Conservative checker: convert only when the flipped form looks like a real word
/// and the typed form does not (or is a known trigger).
public struct LayoutChecker: Sendable {
    private let russianWords: Set<String>
    private let englishWords: Set<String>
    private let alwaysConvert: Set<String>
    private let neverConvert: Set<String>
    private let userRules: [UserRule]

    public init(
        russianWords: Set<String> = SeedDictionary.russian,
        englishWords: Set<String> = SeedDictionary.english,
        alwaysConvert: Set<String> = [],
        neverConvert: Set<String> = [],
        userRules: [UserRule] = []
    ) {
        self.russianWords = russianWords
        self.englishWords = englishWords
        self.alwaysConvert = alwaysConvert
        self.neverConvert = neverConvert
        self.userRules = userRules
    }

    public func check(_ typed: String) -> LayoutCheckResult {
        let word = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 2 else { return .unknown }

        let lower = word.lowercased()

        if neverConvert.contains(lower) { return .exception }
        if alwaysConvert.contains(lower) { return .incorrect }

        for rule in userRules where rule.isActive {
            if matches(rule, word: word) {
                return rule.shouldSwitch ? .incorrect : .exception
            }
        }

        let converted = ConversionEngine.convert(word, direction: .auto)
        let convertedLower = converted.lowercased()

        if convertedLower == lower { return .unknown }

        let typedIsRussianWord = russianWords.contains(lower)
        let typedIsEnglishWord = englishWords.contains(lower)
        let convertedIsRussianWord = russianWords.contains(convertedLower)
        let convertedIsEnglishWord = englishWords.contains(convertedLower)

        // Typed looks fine in current language — leave it.
        if typedIsRussianWord || typedIsEnglishWord {
            return .unknown
        }

        // Only auto-convert when the flipped form is a known dictionary word
        // and the typed form is not. Heuristics caused false positives and
        // mid-word mangling ("пgthtrkxftn").
        if convertedIsRussianWord || convertedIsEnglishWord {
            return .incorrect
        }

        return .unknown
    }

    private func matches(_ rule: UserRule, word: String) -> Bool {
        if rule.isRegex {
            return (try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]))
                .map { regex in
                    let range = NSRange(word.startIndex..., in: word)
                    return regex.firstMatch(in: word, options: [], range: range) != nil
                } ?? false
        }
        return word.caseInsensitiveCompare(rule.pattern) == .orderedSame
    }
}

public enum SeedDictionary: Sendable {
    public static let russian: Set<String> = [
        "привет", "пока", "да", "нет", "спасибо", "пожалуйста", "хорошо", "плохо",
        "сегодня", "завтра", "вчера", "утро", "день", "вечер", "ночь",
        "человек", "люди", "работа", "дом", "время", "жизнь", "слово", "дело",
        "рука", "раз", "глаз", "друг", "лицо", "сторона", "нога", "решение",
        "дверь", "образ", "история", "власть", "закон", "война", "голова", "деньги",
        "машина", "земля", "вода", "отец", "мать", "дочь", "сын", "жена", "муж",
        "город", "улица", "место", "вопрос", "ответ", "письмо", "телефон", "номер",
        "пароль", "логин", "файл", "папка", "окно", "кнопка", "мышь", "клавиатура",
        "сервер", "сайт", "почта", "сообщение", "чат", "канал", "группа",
        "можно", "нужно", "надо", "будет", "было", "есть", "это", "также", "ещё",
        "очень", "только", "уже", "ещё", "когда", "где", "куда", "откуда", "почему",
        "потому", "если", "хотя", "чтобы", "после", "перед", "между", "через",
        "январь", "февраль", "март", "апрель", "июнь", "июль", "август",
        "сентябрь", "октябрь", "ноябрь", "декабрь", "понедельник", "вторник",
        "среда", "четверг", "пятница", "суббота", "воскресенье",
        "здравствуйте", "добрый", "утро", "вечер", "пожалуйста", "извините",
        "конечно", "наверное", "возможно", "действительно", "просто", "сейчас",
        "потом", "здесь", "там", "сюда", "туда", "весь", "вся", "все", "всё",
        "новый", "старый", "большой", "маленький", "хороший", "плохой", "первый",
        "второй", "третий", "последний", "главный", "важный", "нужный",
        "сделать", "сказать", "знать", "хотеть", "видеть", "идти", "прийти",
        "думать", "смотреть", "работать", "жить", "писать", "читать", "говорить",
        "понимать", "помнить", "забыть", "ждать", "любить", "играть", "купить",
        "продать", "открыть", "закрыть", "начать", "кончить", "закончить",
        "проверка", "ошибка", "исправить", "раскладка", "клавиша", "переключить",
        "неправильно", "правильно", "переключает", "переключение", "иногда",
        "одну", "одну", "букву", "несколько", "оставляет", "перевод", "перевода",
        "дублирует", "сейчас", "почему", "потому", "буква", "символ", "текст",
        "набрать", "набрал", "опечатка", "исправление", "слово", "пробел",
    ]

    public static let english: Set<String> = [
        "hello", "hi", "bye", "yes", "no", "thanks", "please", "sorry", "ok", "okay",
        "today", "tomorrow", "yesterday", "morning", "evening", "night", "day",
        "people", "person", "work", "home", "time", "life", "word", "thing",
        "hand", "eye", "friend", "face", "side", "door", "world", "place",
        "question", "answer", "letter", "phone", "number", "password", "login",
        "file", "folder", "window", "button", "mouse", "keyboard", "server",
        "site", "mail", "message", "chat", "channel", "group", "team",
        "can", "need", "will", "was", "were", "been", "have", "has", "had",
        "this", "that", "these", "those", "with", "from", "about", "into",
        "when", "where", "why", "what", "which", "who", "how", "because",
        "if", "though", "after", "before", "between", "through", "during",
        "january", "february", "march", "april", "june", "july", "august",
        "september", "october", "november", "december", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "sunday",
        "good", "bad", "new", "old", "big", "small", "first", "last", "next",
        "make", "say", "know", "want", "see", "come", "think", "look", "take",
        "work", "live", "write", "read", "speak", "talk", "understand",
        "remember", "forget", "wait", "love", "play", "buy", "sell", "open",
        "close", "start", "finish", "check", "error", "fix", "layout", "switch",
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can",
        "her", "was", "one", "our", "out", "day", "get", "has", "him", "his",
        "how", "man", "new", "now", "old", "see", "two", "way", "who", "boy",
        "did", "its", "let", "put", "say", "she", "too", "use",
        "test", "code", "build", "commit", "push", "pull", "branch", "merge",
        "issue", "review", "deploy", "debug", "swift", "apple", "macos", "silicon",
    ]
}
