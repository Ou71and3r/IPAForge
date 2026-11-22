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
    case tooManyEntries
    case expandedSizeLimit
    case unsafePath(String)
    case entrySizeOverflow(String)
    case invalidIPA

    var errorDescription: String? {
        switch self {
        case .cannotAccessFile:
            return "Няма достъп до избрания файл."
        case .invalidArchive:
            return "Файлът не е валиден или не може да бъде прочетен като ZIP/IPA архив."
        case .noDocumentsDirectory:
            return "Не може да бъде открита папката за документи на IPAForge."
        case .tooManyEntries:
            return "Архивът съдържа прекалено много записи (лимит 200 000)."
        case .expandedSizeLimit:
            return "Общият разархивиран размер надвишава защитния лимит от 20 GB."
        case .unsafePath(let path):
            return "Архивът съдържа небезопасен път: \(path)"
        case .entrySizeOverflow(let path):
            return "Размерът на запис в архива е прекалено голям: \(path)"
        case .invalidIPA:
            return "Архивът не съдържа валидна структура Payload/*.app/Info.plist."
        }
    }
}

enum IPAArchiveService {
    private static let maximumEntryCount = 200_000
    private static let maximumExpandedSize: Int64 = 20 * 1024 * 1024 * 1024

    static func copyAndInspect(sourceURL: URL) throws -> IPAArchiveSummary {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
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
            return try inspect(archiveURL: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    static func inspect(archiveURL: URL) throws -> IPAArchiveSummary {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw IPAArchiveError.invalidArchive
        }

        var entryCount = 0
        var totalUncompressedSize: Int64 = 0
        var hasPayload = false
        var appNames = Set<String>()
        var infoPlistCount = 0
        var pathRegistry = IPAArchivePathRegistry()

        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumEntryCount else { throw IPAArchiveError.tooManyEntries }

            do {
                try pathRegistry.register(
                    entry.path,
                    isDirectory: entry.type == .directory,
                    isSymbolicLink: entry.type == .symlink
                )
            } catch let pathError as IPAArchivePathError {
                switch pathError {
                case .unsafePath(let path), .duplicatePath(let path), .symbolicLink(let path):
                    throw IPAArchiveError.unsafePath(path)
                }
            }

            guard entry.uncompressedSize <= UInt64(Int64.max) else {
                throw IPAArchiveError.entrySizeOverflow(path)
            }

            let size = Int64(entry.uncompressedSize)
            let (newTotal, overflow) = totalUncompressedSize.addingReportingOverflow(size)
            guard !overflow, newTotal <= maximumExpandedSize else {
                throw IPAArchiveError.expandedSizeLimit
            }
            totalUncompressedSize = newTotal

            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if components.first == "Payload" {
                hasPayload = true
                if components.count >= 2, components[1].hasSuffix(".app") {
                    appNames.insert(components[1])
                }
                if components.count == 3, components[1].hasSuffix(".app"), components[2] == "Info.plist" {
                    infoPlistCount += 1
                }
            }
        }

        guard hasPayload, !appNames.isEmpty, infoPlistCount > 0 else {
            throw IPAArchiveError.invalidIPA
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
