import Foundation
import ZIPFoundation
import RorkSign

enum IPASigningError: LocalizedError {
    case missingPayload
    case missingBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .missingPayload: return "В архива не е открито приложение в Payload."
        case .missingBundleIdentifier: return "Не може да бъде прочетен Bundle Identifier от Info.plist."
        }
    }
}

enum IPASigningService {
    static func sign(ipaURL: URL, p12URL: URL, profileURL: URL, password: String) async throws -> URL {
        let fm = FileManager.default
        let p12 = try Data(contentsOf: p12URL, options: .mappedIfSafe)
        let profile = try Data(contentsOf: profileURL, options: .mappedIfSafe)
        let identity = try SigningIdentity(pkcs12Data: p12, password: password)

        let archive = try Archive(url: ipaURL, accessMode: .read)
        guard let appInfoEntry = archive.first(where: {
            $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/Info.plist")
        }) else {
            throw IPASigningError.missingPayload
        }

        let temporaryInfoURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        defer { try? fm.removeItem(at: temporaryInfoURL) }
        _ = try archive.extract(appInfoEntry, to: temporaryInfoURL)
        let infoData = try Data(contentsOf: temporaryInfoURL)
        guard
            let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any],
            let bundleIdentifier = info["CFBundleIdentifier"] as? String,
            !bundleIdentifier.isEmpty
        else {
            throw IPASigningError.missingBundleIdentifier
        }

        let outputDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory
            .appendingPathComponent(ipaURL.deletingPathExtension().lastPathComponent + "-signed")
            .appendingPathExtension("ipa")
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }

        try await RorkSigner.signIPA(
            at: ipaURL,
            outputURL: outputURL,
            identity: identity,
            options: AppSigningOptions(
                bundleIdentifier: bundleIdentifier,
                rootProvisioningProfile: profile
            )
        )
        return outputURL
    }
}
