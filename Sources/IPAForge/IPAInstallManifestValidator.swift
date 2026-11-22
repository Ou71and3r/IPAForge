import Foundation

enum IPAInstallManifestError: LocalizedError, Equatable {
    case malformedPropertyList
    case missingSoftwarePackage
    case packageURLMismatch
    case metadataMismatch

    var errorDescription: String? {
        switch self {
        case .malformedPropertyList:
            return "Услугата върна невалиден инсталационен manifest."
        case .missingSoftwarePackage:
            return "Manifest-ът не съдържа необходимия software-package запис."
        case .packageURLMismatch:
            return "Manifest-ът сочи към различен IPA адрес. Инсталацията е прекратена."
        case .metadataMismatch:
            return "Метаданните в manifest-а не съвпадат с избраното приложение."
        }
    }
}

enum IPAInstallManifestValidator {
    static func validate(
        _ data: Data,
        expectedPackageURL: URL,
        bundleIdentifier: String,
        displayName: String,
        version: String
    ) throws {
        guard let root = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        let items = root["items"] as? [[String: Any]],
        !items.isEmpty else {
            throw IPAInstallManifestError.malformedPropertyList
        }

        var packageURLString: String?
        var metadata: [String: Any]?

        for item in items {
            if let assets = item["assets"] as? [[String: Any]],
               let package = assets.first(where: {
                   ($0["kind"] as? String) == "software-package"
               }) {
                packageURLString = package["url"] as? String
            }
            if let candidate = item["metadata"] as? [String: Any] {
                metadata = candidate
            }
        }

        guard let packageURLString,
              let packageURL = URL(string: packageURLString) else {
            throw IPAInstallManifestError.missingSoftwarePackage
        }
        guard packageURL.absoluteString == expectedPackageURL.absoluteString else {
            throw IPAInstallManifestError.packageURLMismatch
        }
        guard let metadata,
              metadata["bundle-identifier"] as? String == bundleIdentifier,
              metadata["bundle-version"] as? String == version,
              metadata["title"] as? String == displayName,
              metadata["kind"] as? String == "software" else {
            throw IPAInstallManifestError.metadataMismatch
        }
    }
}
