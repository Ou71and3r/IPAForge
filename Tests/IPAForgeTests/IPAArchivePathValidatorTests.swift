import XCTest
@testable import IPAForge

final class IPAArchivePathValidatorTests: XCTestCase {
    func testAcceptsNormalIPAPaths() throws {
        try IPAArchivePathValidator.validate("Payload/Example.app/Info.plist")
        try IPAArchivePathValidator.validate("Payload/Example.app/Frameworks/")
        try IPAArchivePathValidator.validate("Payload/Example.app/Frameworks/Kit.framework/Kit")
    }

    func testRejectsTraversalAndAbsolutePaths() {
        let paths = ["../outside", "Payload/../../outside", "/Payload/App", "//server/share", "C:/Payload/App"]
        for path in paths {
            XCTAssertThrowsError(try IPAArchivePathValidator.validate(path), path)
        }
    }

    func testRejectsWindowsAndMalformedComponents() {
        let paths = ["Payload\\App", "Payload//App", "Payload/./App", "Payload/App:stream", "Payload/"]
        for path in paths {
            XCTAssertThrowsError(try IPAArchivePathValidator.validate(path), path)
        }
    }

    func testRejectsEmptyAndNULPaths() {
        XCTAssertThrowsError(try IPAArchivePathValidator.validate(""))
        XCTAssertThrowsError(try IPAArchivePathValidator.validate("Payload/App\0/Info.plist"))
    }

    func testCollisionKeyIgnoresCaseAndUnicodeComposition() {
        XCTAssertEqual(
            IPAArchivePathValidator.collisionKey(for: "Payload/Café.app/Info.plist"),
            IPAArchivePathValidator.collisionKey(for: "payload/Cafe\u{0301}.APP/INFO.PLIST")
        )
    }
}
