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

        // The package asset and metadata must belong to the same manifest item.
        // Never combine fields from separate items when validating the installer response.
        var foundPackage = false
        var foundMatchingPackageURL = false
        var foundMetadata = false

        for item in items {
            guard let assets = item["assets"] as? [[String: Any]],
                  let package = assets.first(where: {
                      ($0["kind"] as? String) == "software-package"
                  }) else {
                continue
            }
            foundPackage = true

            guard let packageURLString = package["url"] as? String,
                  let packageURL = URL(string: packageURLString),
                  packageURL.absoluteString == expectedPackageURL.absoluteString else {
                continue
            }
            foundMatchingPackageURL = true

            guard let metadata = item["metadata"] as? [String: Any],
                  metadata["bundle-identifier"] as? String == bundleIdentifier,
                  metadata["bundle-version"] as? String == version,
                  metadata["title"] as? String == displayName,
                  metadata["kind"] as? String == "software" else {
                continue
            }
            foundMetadata = true
            break
        }

        guard foundPackage else {
            throw IPAInstallManifestError.missingSoftwarePackage
        }
        guard foundMatchingPackageURL else {
            throw IPAInstallManifestError.packageURLMismatch
        }
        guard foundMetadata else {
            throw IPAInstallManifestError.metadataMismatch
        }
    }
}
