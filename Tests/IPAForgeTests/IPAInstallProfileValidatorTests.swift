import XCTest
@testable import IPAForge

final class IPAInstallProfileValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAcceptsAdHocProfileWithRegisteredDevices() throws {
        try IPAInstallProfileValidator.validate(profile(
            expiration: now.addingTimeInterval(3600),
            devices: ["00008020-DEVICE"]
        ), now: now)
    }

    func testAcceptsEnterpriseProfile() throws {
        try IPAInstallProfileValidator.validate(profile(
            expiration: now.addingTimeInterval(3600),
            enterprise: true
        ), now: now)
    }

    func testRejectsAppStoreProfileWithoutDevices() {
        XCTAssertThrowsError(try IPAInstallProfileValidator.validate(
            profile(expiration: now.addingTimeInterval(3600)),
            now: now
        )) { error in
            XCTAssertEqual(error as? IPAInstallProfileError, .notEligible)
        }
    }

    func testRejectsExpiredProfile() {
        XCTAssertThrowsError(try IPAInstallProfileValidator.validate(
            profile(expiration: now.addingTimeInterval(-1), devices: ["DEVICE"]),
            now: now
        )) { error in
            XCTAssertEqual(error as? IPAInstallProfileError, .expired)
        }
    }

    func testRejectsMalformedProfile() {
        XCTAssertThrowsError(try IPAInstallProfileValidator.validate(Data("not a profile".utf8), now: now))
    }

    private func profile(
        expiration: Date,
        devices: [String] = [],
        enterprise: Bool = false
    ) -> Data {
        var values: [String: Any] = [
            "ExpirationDate": expiration,
            "ProvisionedDevices": devices
        ]
        if enterprise { values["ProvisionsAllDevices"] = true }
        let plist = try! PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        return Data("CMS envelope\n".utf8) + plist + Data("\nCMS trailer".utf8)
    }
}
