import Foundation
import ZIPFoundation
import RorkSign

enum IPASigningError: LocalizedError {
    case missingPayload
    case missingBundleIdentifier
    case missingRootProfile(bundleIdentifier: String, profiles: [String])
    case noMatchingProfile(String)
    case unsupportedBundleRewrite(components: [String])
    case ambiguousProfiles(String)
    case expiredProfile(String)
    case outputValidationFailed
    case insufficientStorage(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "В архива не е открито приложение в Payload."
        case .missingBundleIdentifier:
            return "Не може да бъде прочетен Bundle Identifier от Info.plist."
        case .missingRootProfile(let bundleIdentifier, let profiles):
            let details = profiles.isEmpty
                ? "Няма прочетени provisioning профили."
                : profiles.joined(separator: "\n")
            return "Няма provisioning профил, който разрешава основното приложение.\nBundle ID на IPA: \(bundleIdentifier)\n\nИмпортирани профили:\n\(details)\n\nP12 сертификатът е приет от проверката за съответствие с профила."
        case .noMatchingProfile(let identifier):
            return "Няма provisioning профил за вложения компонент: \(identifier)"
        case .unsupportedBundleRewrite(let components):
            let details = components.isEmpty
                ? "Не бяха прочетени подробности за вложените компоненти."
                : components.joined(separator: "\n")
            return "Основният Bundle ID трябва да бъде променен, но IPA съдържа вложени компоненти. Ето диагностиката:\n\n\(details)\n\nДобави съвместими provisioning профили за компонентите без съвпадение. Оригиналният IPA не е променен."
        case .ambiguousProfiles(let identifier):
            return "Няколко provisioning профила съвпадат с \(identifier). Остави само правилния профил."
        case .expiredProfile(let identifier):
            return "Provisioning профилът за \(identifier) е изтекъл."
        case .outputValidationFailed:
            return "Подписването приключи, но полученият IPA не премина проверката за структура. Файлът няма да бъде експортиран."
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
        let rootProfile: (url: URL, data: Data, profile: ProvisioningProfile)
        let signingBundleIdentifier: String
        if let exactProfile = try selectProfile(for: rootIdentifier, from: profiles) {
            rootProfile = exactProfile
            signingBundleIdentifier = rootIdentifier
        } else {
            // Rebase only to a single explicit App ID authorized by the selected
            // credential. Wildcard profiles and ambiguous choices are not guessed.
            let candidates = profiles.filter {
                !$0.profile.isExpired()
                    && $0.profile.explicitAuthorizedBundleIdentifier != nil
            }
            guard candidates.count == 1,
                  let replacementIdentifier = candidates.first?.profile.explicitAuthorizedBundleIdentifier else {
                let diagnostics = profiles.map { item in
                    let appID = item.profile.applicationIdentifier ?? "(липсва application-identifier)"
                    let teamID = item.profile.teamIdentifier
                    let pattern = item.profile.authorizedBundleIdentifier ?? "(неразпознат App ID)"
                    return "• \(item.url.lastPathComponent): App ID \(appID); Team ID \(teamID); шаблон \(pattern)"
                }
                throw IPASigningError.missingRootProfile(
                    bundleIdentifier: rootIdentifier,
                    profiles: diagnostics
                )
            }
            rootProfile = candidates[0]
            signingBundleIdentifier = replacementIdentifier
        }
        guard !rootProfile.profile.isExpired() else {
            throw IPASigningError.expiredProfile(signingBundleIdentifier)
        }

        if signingBundleIdentifier != rootIdentifier {
            var nestedComponents: [String] = []
            for entry in archive where entry.path.hasPrefix("Payload/") && entry.path.hasSuffix("/Info.plist") {
                let parts = entry.path.split(separator: "/")
                guard parts.count >= 4 else { continue }
                let name = String(parts.dropLast().last ?? "")
                guard name.hasSuffix(".appex") || name.hasSuffix(".app") else { continue }

                let identifier = try readBundleIdentifier(from: entry)
                let matchingProfiles = profiles.filter {
                    $0.profile.supportsBundleIdentifier(identifier)
                }
                let profileStatus: String
                if matchingProfiles.isEmpty {
                    profileStatus = "НЯМА съвместим профил"
                } else if matchingProfiles.count > 1 {
                    profileStatus = "НЯКОЛКО съвместими профила (\(matchingProfiles.count))"
                } else if matchingProfiles[0].profile.isExpired() {
                    profileStatus = "Профилът е изтекъл"
                } else {
                    profileStatus = "Има съвместим профил"
                }
                nestedComponents.append("\(name) — \(identifier) — \(profileStatus)")
            }
            guard nestedComponents.isEmpty else {
                throw IPASigningError.unsupportedBundleRewrite(components: nestedComponents)
            }
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

        var outputDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var outputDirectoryValues = URLResourceValues()
        outputDirectoryValues.isExcludedFromBackup = true
        try outputDirectory.setResourceValues(outputDirectoryValues)
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: outputDirectory.path
        )
        let outputURL = uniqueOutputURL(
            in: outputDirectory,
            baseName: ipaURL.deletingPathExtension().lastPathComponent + "-signed",
            fileManager: fm
        )
        var temporaryOutputURL = outputDirectory
            .appendingPathComponent(".\(UUID().uuidString).partial")
            .appendingPathExtension("ipa")
        defer { try? fm.removeItem(at: temporaryOutputURL) }

        guard let applicationSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw IPAArchiveError.noDocumentsDirectory
        }
        var workspaceRoot = applicationSupport.appendingPathComponent(
            "SigningWorkspaces",
            isDirectory: true
        )
        try fm.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        var rootValues = URLResourceValues()
        rootValues.isExcludedFromBackup = true
        try workspaceRoot.setResourceValues(rootValues)
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: workspaceRoot.path
        )
        cleanupStaleArtifacts(
            in: workspaceRoot,
            outputDirectory: outputDirectory,
            fileManager: fm
        )

        let operationWorkspace = workspaceRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try fm.createDirectory(at: operationWorkspace, withIntermediateDirectories: false)
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: operationWorkspace.path
        )
        defer { try? fm.removeItem(at: operationWorkspace) }

        try RorkSigner.signIPA(
            at: ipaURL,
            outputURL: temporaryOutputURL,
            identity: identity,
            options: AppSigningOptions(
                bundleIdentifier: signingBundleIdentifier,
                rootProvisioningProfile: rootProfile.data,
                provisioningProfilesByBundleIdentifier: profilesByBundleIdentifier
            ),
            archiveCompressionMode: .deflated,
            temporaryDirectory: operationWorkspace
        )

        try fm.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: temporaryOutputURL.path
        )
        var temporaryOutputValues = URLResourceValues()
        temporaryOutputValues.isExcludedFromBackup = true
        try temporaryOutputURL.setResourceValues(temporaryOutputValues)

        // Validate the completed archive before publishing it to the user.
        let signedSummary = try IPAArchiveService.inspect(archiveURL: temporaryOutputURL)
        guard signedSummary.hasPayload,
              signedSummary.appBundleNames == summary.appBundleNames else {
            throw IPASigningError.outputValidationFailed
        }

        try fm.moveItem(at: temporaryOutputURL, to: outputURL)
        return outputURL
    }

    /// Removes abandoned workspaces and hidden partial outputs left behind if
    /// the app was terminated before the normal defer-based cleanup ran.
    private static func cleanupStaleArtifacts(
        in workspaceRoot: URL,
        outputDirectory: URL,
        fileManager: FileManager
    ) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]

        if let workspaces = try? fileManager.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) {
            for workspace in workspaces {
                let values = try? workspace.resourceValues(forKeys: keys)
                guard values?.isDirectory == true,
                      let modified = values?.contentModificationDate,
                      modified < cutoff else {
                    continue
                }
                try? fileManager.removeItem(at: workspace)
            }
        }

        if let outputs = try? fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) {
            for partial in outputs where partial.lastPathComponent.hasPrefix(".")
                && partial.lastPathComponent.hasSuffix(".partial.ipa") {
                let values = try? partial.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modified = values?.contentModificationDate,
                      modified < cutoff else {
                    continue
                }
                try? fileManager.removeItem(at: partial)
            }
        }
    }

    private static func uniqueOutputURL(
        in directory: URL,
        baseName: String,
        fileManager: FileManager
    ) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
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
