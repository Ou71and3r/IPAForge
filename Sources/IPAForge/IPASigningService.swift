import Foundation
import ZIPFoundation
import RorkSign

enum IPASigningError: LocalizedError {
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .missingPayload: return "В архива не е открито приложение в Payload."
        }
    }
}

enum IPASigningService {
    static func sign(ipaURL: URL, p12URL: URL, profileURL: URL, password: String) throws -> URL {
        let fm = FileManager.default
        let p12 = try Data(contentsOf: p12URL, options: .mappedIfSafe)
        let profile = try Data(contentsOf: profileURL, options: .mappedIfSafe)
        let identity = try SigningIdentity(pkcs12Data: p12, password: password)

        let archive = try Archive(url: ipaURL, accessMode: .read)
        guard archive.contains(where: { $0.path.hasPrefix("Payload/") && $0.path.contains(".app/") }) else {
            throw IPASigningError.missingPayload
        }

        let outputDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory
            .appendingPathComponent(ipaURL.deletingPathExtension().lastPathComponent + "-signed")
            .appendingPathExtension("ipa")
        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }

        try RorkSigner.signIPA(
            at: ipaURL,
            outputURL: outputURL,
            identity: identity,
            options: AppSigningOptions(rootProvisioningProfile: profile)
        )
        return outputURL
    }
}
