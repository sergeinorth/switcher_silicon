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

        // Converted looks like a real word — wrong layout.
        if convertedIsRussianWord || convertedIsEnglishWord {
            return .incorrect
        }

        // Heuristic: pure latin that maps to cyrillic letters of length >= 3
        // and contains no vowels typical for English nonsense like "asdf".
        if ConversionEngine.dominantScript(word) == .latin,
           converted.contains(where: { !$0.isASCII }),
           word.count >= 3,
           looksLikeMistypedRussian(lower)
        {
            return .incorrect
        }

        if ConversionEngine.dominantScript(word) == .cyrillic,
           converted.allSatisfy({ $0.isASCII || !$0.isLetter }),
           word.count >= 3,
           looksLikeMistypedEnglish(lower)
        {
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

    private func looksLikeMistypedRussian(_ lower: String) -> Bool {
        // Common English-looking garbage that is actually Russian on wrong layout.
        let russianVowelKeys: Set<Character> = ["f", "a", "t", "u", "e", "n", "y", "o", "`"]
        return lower.contains(where: { russianVowelKeys.contains($0) })
    }

    private func looksLikeMistypedEnglish(_ lower: String) -> Bool {
        let englishVowelKeys: Set<Character> = ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э", "я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
        // If it has many cyrillic letters that sit on Latin vowel positions when flipped.
        let flipped = ConversionEngine.convert(lower, direction: .russianToUs)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        return flipped.contains(where: { vowels.contains($0) }) || lower.contains(where: { englishVowelKeys.contains($0) })
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
