import Foundation

enum HotwordsStore {
    static let userDefaultsKey = "v2a.hotwords.v1"

    static func load() -> [String] {
        guard let arr = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return []
        }
        return arr.filter { !$0.isEmpty }
    }

    static func save(_ words: [String]) {
        UserDefaults.standard.set(words, forKey: userDefaultsKey)
    }

    static func parse(_ input: String) -> [String] {
        input
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
