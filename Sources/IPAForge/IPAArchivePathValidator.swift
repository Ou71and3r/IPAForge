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
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
        return normalized.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Tracks archive paths in O(total path depth), avoiding repeated full-set scans
/// when validating archives containing very large numbers of entries.
struct IPAArchivePathRegistry {
    private var seenPaths = Set<String>()
    private var seenFiles = Set<String>()
    private var seenDirectories = Set<String>()
    private var pathsWithDescendants = Set<String>()

    mutating func register(
        _ path: String,
        isDirectory: Bool,
        isSymbolicLink: Bool = false
    ) throws {
        try IPAArchivePathValidator.validate(path)
        guard !isSymbolicLink else {
            throw IPAArchivePathError.symbolicLink(path)
        }

        let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        let key = IPAArchivePathValidator.collisionKey(for: normalizedPath)
        guard seenPaths.insert(key).inserted else {
            throw IPAArchivePathError.duplicatePath(path)
        }

        let components = normalizedPath.split(separator: "/").map(String.init)
        var ancestors: [String] = []
        var ancestor = ""
        for component in components.dropLast() {
            ancestor = ancestor.isEmpty ? component : ancestor + "/" + component
            let ancestorKey = IPAArchivePathValidator.collisionKey(for: ancestor)
            guard !seenFiles.contains(ancestorKey) else {
                throw IPAArchivePathError.unsafePath(path)
            }
            ancestors.append(ancestorKey)
        }

        if isDirectory {
            guard !seenFiles.contains(key) else {
                throw IPAArchivePathError.unsafePath(path)
            }
            seenDirectories.insert(key)
        } else {
            guard !seenDirectories.contains(key),
                  !pathsWithDescendants.contains(key) else {
                throw IPAArchivePathError.unsafePath(path)
            }
            seenFiles.insert(key)
        }

        pathsWithDescendants.formUnion(ancestors)
    }
}
