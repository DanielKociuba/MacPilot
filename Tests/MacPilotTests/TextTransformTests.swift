import XCTest
@testable import MacPilot
final class TextTransformTests: XCTestCase {
    func testUniqueLinesPreservesOrderAndWhitespace() {
        XCTAssertEqual(TextTransform.uniqueLines("b\na\nb\n a"), "b\na\n a")
    }
    func testJSONRejectsMalformedInput() { XCTAssertThrowsError(try TextTransform.prettyJSON("{broken")) }
    func testJSONSupportsScalar() throws { XCTAssertEqual(try TextTransform.prettyJSON("42"), "42") }
}
