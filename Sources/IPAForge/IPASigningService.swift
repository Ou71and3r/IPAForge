import Foundation
import ZIPFoundation
import RorkSign

enum IPASigningError: LocalizedError {
    case missingPayload
    case missingBundleIdentifier
    case missingRootProfile
    case noMatchingProfile(String)
    case ambiguousProfiles(String)
    case expiredProfile(String)
    case insufficientStorage(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "В архива не е открито приложение в Payload."
        case .missingBundleIdentifier:
            return "Не може да бъде прочетен Bundle Identifier от Info.plist."
        case .missingRootProfile:
            return "Не е избран provisioning профил, който разрешава основното приложение."
        case .noMatchingProfile(let identifier):
            return "Няма provisioning профил за вложения компонент: \(identifier)"
        case .ambiguousProfiles(let identifier):
            return "Няколко provisioning профила съвпадат с \(identifier). Остави само правилния профил."
        case .expiredProfile(let identifier):
            return "Provisioning профилът за \(identifier) е изтекъл."
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Недостатъчно свободно място. Необходими са приблизително \(formatter.string(fromByteCount: required)), налични са \(formatter.string(fromByteCount: available)). Освободи място и опитай отново."
        }
    }
}

enum IPASigningService {
    private static let additionalStorageHeadroom: Int64 = 512 * 1024 * 1024

    static func sign(ipaURL: URL, p12URL: URL, profileURLs: [URL], password: String) throws -> URL {
        let fm = FileManager.default
        let summary = try IPAArchiveService.inspect(archiveURL: ipaURL)
        let (twiceExpanded, overflowA) = summary.uncompressedSize.multipliedReportingOverflow(by: 2)
        let (withInput, overflowB) = twiceExpanded.addingReportingOverflow(summary.fileSize)
        let (required, overflowC) = withInput.addingReportingOverflow(additionalStorageHeadroom)
        guard !overflowA, !overflowB, !overflowC else {
            throw IPAArchiveError.expandedSizeLimit
        }

        let storageValues = try ipaURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available = storageValues.volumeAvailableCapacityForImportantUsage
            ?? Int64(storageValues.volumeAvailableCapacity ?? 0)
        guard available >= required else {
            throw IPASigningError.insufficientStorage(required: required, available: available)
        }

        let p12 = try Data(contentsOf: p12URL, options: .mappedIfSafe)
        let identity = try SigningIdentity(pkcs12Data: p12, password: password)
        let profiles = try profileURLs.map { url -> (url: URL, data: Data, profile: ProvisioningProfile) in
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let profile = try RorkSigner.decodeProvisioningProfile(data)
            // Ensure every selected profile authorizes the private-key identity
            // before it is considered for a bundle.
            _ = try RorkSigner.checkProfileCredential(
                provisioningProfile: profile,
                credentialData: p12,
                password: password
            )
            return (url, data, profile)
        }

        let archive = try Archive(url: ipaURL, accessMode: .read)
        let rootInfoEntry = archive.first(where: {
            let parts = $0.path.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        })
        guard let rootInfoEntry else { throw IPASigningError.missingPayload }

        let inspectionDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: inspectionDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: inspectionDirectory) }

        func readBundleIdentifier(from entry: Entry) throws -> String {
            let fileURL = inspectionDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: fileURL) }
            _ = try archive.extract(entry, to: fileURL)
            let data = try Data(contentsOf: fileURL)
            guard let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let identifier = info["CFBundleIdentifier"] as? String,
                  !identifier.isEmpty else {
                throw IPASigningError.missingBundleIdentifier
            }
            return identifier
        }

        let rootIdentifier = try readBundleIdentifier(from: rootInfoEntry)
        guard let rootProfile = try selectProfile(for: rootIdentifier, from: profiles) else {
            throw IPASigningError.missingRootProfile
        }
        guard !rootProfile.profile.isExpired() else {
            throw IPASigningError.expiredProfile(rootIdentifier)
        }

        var profilesByBundleIdentifier: [String: Data] = [:]
        for entry in archive where entry.path.hasPrefix("Payload/") && entry.path.hasSuffix("/Info.plist") {
            let parts = entry.path.split(separator: "/")
            guard parts.count >= 4 else { continue }
            let identifier = try readBundleIdentifier(from: entry)
            if identifier == rootIdentifier { continue }
            guard let selected = try selectProfile(for: identifier, from: profiles) else {
                // Frameworks and resource bundles are not independently provisioned.
                let bundleDirectory = parts.dropLast().last ?? ""
                let isProvisionedBundle = bundleDirectory.hasSuffix(".appex")
                    || bundleDirectory.hasSuffix(".app")
                if isProvisionedBundle {
                    throw IPASigningError.noMatchingProfile(identifier)
                }
                continue
            }
            guard !selected.profile.isExpired() else {
                throw IPASigningError.expiredProfile(identifier)
            }
            profilesByBundleIdentifier[identifier] = selected.data
        }

        let outputDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = uniqueOutputURL(
            in: outputDirectory,
            baseName: ipaURL.deletingPathExtension().lastPathComponent + "-signed",
            fileManager: fm
        )
        let temporaryOutputURL = outputDirectory
            .appendingPathComponent(".\\(UUID().uuidString).partial")
            .appendingPathExtension("ipa")
        defer { try? fm.removeItem(at: temporaryOutputURL) }

        try RorkSigner.signIPA(
            at: ipaURL,
            outputURL: temporaryOutputURL,
            identity: identity,
            options: AppSigningOptions(
                bundleIdentifier: rootIdentifier,
                rootProvisioningProfile: rootProfile.data,
                provisioningProfilesByBundleIdentifier: profilesByBundleIdentifier
            )
        )
        try fm.moveItem(at: temporaryOutputURL, to: outputURL)
        return outputURL
    }

    private static func uniqueOutputURL(
        in directory: URL,
        baseName: String,
        fileManager: FileManager
    ) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\\(baseName)-\\(suffix)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension("ipa")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func selectProfile(
        for bundleIdentifier: String,
        from profiles: [(url: URL, data: Data, profile: ProvisioningProfile)]
    ) throws -> (url: URL, data: Data, profile: ProvisioningProfile)? {
        let matches = profiles.filter { $0.profile.supportsBundleIdentifier(bundleIdentifier) }
        guard !matches.isEmpty else { return nil }
        let exact = matches.filter { $0.profile.explicitAuthorizedBundleIdentifier == bundleIdentifier }
        let preferred = exact.isEmpty ? matches : exact
        guard preferred.count == 1 else {
            throw IPASigningError.ambiguousProfiles(bundleIdentifier)
        }
        return preferred[0]
    }
}
