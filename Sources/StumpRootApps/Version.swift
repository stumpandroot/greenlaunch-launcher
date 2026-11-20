import Foundation

/// A version like `1.2.3`, read from tags such as `v1.2.3` or `v2.0.0-beta`.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let core = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        return (0..<count).allSatisfy { lhs.part($0) == rhs.part($0) }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count where lhs.part(index) != rhs.part(index) {
            return lhs.part(index) < rhs.part(index)
        }
        return false
    }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Shows a tag as `v1.2.3`.
func displayVersion(_ text: String) -> String {
    text.hasPrefix("v") || text.hasPrefix("V") ? text : "v" + text
}

enum Machine {
    static var isARM: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
