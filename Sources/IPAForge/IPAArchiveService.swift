import Foundation
import ZIPFoundation

struct IPAArchiveSummary {
    let fileName: String
    let fileSize: Int64
    let entryCount: Int
    let uncompressedSize: Int64
    let hasPayload: Bool
    let appBundleNames: [String]
    let infoPlistCount: Int
    let localURL: URL
}

enum IPAArchiveError: LocalizedError {
    case cannotAccessFile
    case invalidArchive
    case noDocumentsDirectory

    var errorDescription: String? {
        switch self {
        case .cannotAccessFile:
            return "Няма достъп до избрания файл."
        case .invalidArchive:
            return "Файлът не е валиден или не може да бъде прочетен като ZIP/IPA архив."
        case .noDocumentsDirectory:
            return "Не може да бъде открита папката за документи на IPAForge."
        }
    }
}

enum IPAArchiveService {
    static func copyAndInspect(sourceURL: URL) throws -> IPAArchiveSummary {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw IPAArchiveError.cannotAccessFile
        }

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw IPAArchiveError.noDocumentsDirectory
        }

        let importsDirectory = documents.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)

        let destinationURL = importsDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ipa")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw error
        }

        do {
            return try inspect(archiveURL: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            if error is IPAArchiveError {
                throw error
            }
            throw IPAArchiveError.invalidArchive
        }
    }

    static func inspect(archiveURL: URL) throws -> IPAArchiveSummary {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw IPAArchiveError.invalidArchive
        }

        var entryCount = 0
        var totalUncompressedSize: Int64 = 0
        var hasPayload = false
        var appNames = Set<String>()
        var infoPlistCount = 0

        for entry in archive {
            entryCount += 1
            totalUncompressedSize += Int64(entry.uncompressedSize)

            let path = entry.path
            let components = path.split(separator: "/").map(String.init)

            if components.first == "Payload" {
                hasPayload = true
                if components.count >= 2, components[1].hasSuffix(".app") {
                    appNames.insert(components[1])
                }
                if components.count == 3, components[2] == "Info.plist" {
                    infoPlistCount += 1
                }
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return IPAArchiveSummary(
            fileName: archiveURL.lastPathComponent,
            fileSize: fileSize,
            entryCount: entryCount,
            uncompressedSize: totalUncompressedSize,
            hasPayload: hasPayload,
            appBundleNames: appNames.sorted(),
            infoPlistCount: infoPlistCount,
            localURL: archiveURL
        )
    }
}
