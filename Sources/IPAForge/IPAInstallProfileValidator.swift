import Foundation

enum IPAInstallProfileError: LocalizedError {
    case missingProfile
    case unreadableProfile
    case expired
    case notEligible

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "В подписания IPA липсва embedded.mobileprovision за основното приложение."
        case .unreadableProfile:
            return "Provisioning профилът в IPA не може да бъде прочетен."
        case .expired:
            return "Provisioning профилът е изтекъл."
        case .notEligible:
            return "Профилът не позволява OTA инсталиране. Необходим е Ad Hoc профил с регистрирани устройства или Enterprise профил."
        }
    }
}

enum IPAInstallProfileValidator {
    static func validate(_ data: Data, now: Date = Date()) throws {
        guard let plistData = embeddedPropertyList(in: data),
              let profile = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ) as? [String: Any] else {
            throw IPAInstallProfileError.unreadableProfile
        }

        guard let expiration = profile["ExpirationDate"] as? Date else {
            throw IPAInstallProfileError.unreadableProfile
        }
        guard expiration > now else {
            throw IPAInstallProfileError.expired
        }

        let enterprise = (profile["ProvisionsAllDevices"] as? Bool) == true
        let devices = profile["ProvisionedDevices"] as? [String] ?? []
        guard enterprise || !devices.isEmpty else {
            throw IPAInstallProfileError.notEligible
        }
    }

    private static func embeddedPropertyList(in data: Data) -> Data? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker),
              let end = data.range(of: endMarker, options: [], in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}
