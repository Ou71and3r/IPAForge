import Foundation

enum IPAArchivePathError: LocalizedError {
    case unsafePath(String)
    case duplicatePath(String)
    case symbolicLink(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path): return "Небезопасен път в архива: \(path)"
        case .duplicatePath(let path): return "Дублиран или конфликтен път в архива: \(path)"
        case .symbolicLink(let path): return "Символните връзки не се поддържат: \(path)"
        }
    }
}

enum IPAArchivePathValidator {
    static func validate(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw IPAArchivePathError.unsafePath(path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let meaningful = path.hasSuffix("/") ? Array(components.dropLast()) : components
        guard !meaningful.isEmpty,
              !meaningful.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !meaningful[0].contains(":"),
              !meaningful.contains(where: { $0.contains(":") }) else {
            throw IPAArchivePathError.unsafePath(path)
        }
    }

    static func collisionKey(for path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
