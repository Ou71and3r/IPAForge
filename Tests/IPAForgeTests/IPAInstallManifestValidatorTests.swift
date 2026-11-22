import XCTest
@testable import IPAForge

final class IPAInstallManifestValidatorTests: XCTestCase {
    private let packageURL = URL(string: "http://127.0.0.1:34567/app.ipa")!

    func testAcceptsMatchingManifest() throws {
        try IPAInstallManifestValidator.validate(
            manifest(packageURL: packageURL.absoluteString),
            expectedPackageURL: packageURL,
            bundleIdentifier: "com.example.demo",
            displayName: "Demo App",
            version: "2.1"
        )
    }

    func testRejectsManifestPointingToDifferentPackageURL() {
        XCTAssertThrowsError(try IPAInstallManifestValidator.validate(
            manifest(packageURL: "https://example.com/other.ipa"),
            expectedPackageURL: packageURL,
            bundleIdentifier: "com.example.demo",
            displayName: "Demo App",
            version: "2.1"
        )) { error in
            XCTAssertEqual(error as? IPAInstallManifestError, .packageURLMismatch)
        }
    }

    func testRejectsMismatchedBundleIdentifier() {
        XCTAssertThrowsError(try IPAInstallManifestValidator.validate(
            manifest(bundleIdentifier: "com.example.other"),
            expectedPackageURL: packageURL,
            bundleIdentifier: "com.example.demo",
            displayName: "Demo App",
            version: "2.1"
        )) { error in
            XCTAssertEqual(error as? IPAInstallManifestError, .metadataMismatch)
        }
    }

    func testRejectsMalformedManifest() {
        XCTAssertThrowsError(try IPAInstallManifestValidator.validate(
            Data("not a plist".utf8),
            expectedPackageURL: packageURL,
            bundleIdentifier: "com.example.demo",
            displayName: "Demo App",
            version: "2.1"
        )) { error in
            XCTAssertEqual(error as? IPAInstallManifestError, .malformedPropertyList)
        }
    }

    private func manifest(
        packageURL: String? = nil,
        bundleIdentifier: String = "com.example.demo"
    ) -> Data {
        let value: [String: Any] = [
            "items": [[
                "assets": [[
                    "kind": "software-package",
                    "url": packageURL ?? self.packageURL.absoluteString
                ]],
                "metadata": [
                    "bundle-identifier": bundleIdentifier,
                    "bundle-version": "2.1",
                    "kind": "software",
                    "title": "Demo App"
                ]
            ]]
        ]
        return try! PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
    }
}
