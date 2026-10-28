import XCTest
import AppKit
import ImageIO
@testable import MacPilot

final class FileWorkflowTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testUndoRestoresMovedFile() throws {
        let source = root.appendingPathComponent("original")
        let dest = root.appendingPathComponent("moved")
        try Data("original".utf8).write(to: source)
        let identity = try FileSafety.identity(source)
        try FileManager.default.moveItem(at: source, to: dest)
        try FileSafety.restore(MoveRecord(source: source, destination: dest, identity: identity, reason: "Test"))
        XCTAssertEqual(try String(contentsOf: source), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }
    func testUndoRefusesOccupiedOriginal() throws {
        let source = root.appendingPathComponent("original")
        let dest = root.appendingPathComponent("moved")
        try Data("keep".utf8).write(to: source)
        try Data("moved".utf8).write(to: dest)
        let record = MoveRecord(source: source, destination: dest, identity: try FileSafety.identity(dest), reason: "Test")
        XCTAssertThrowsError(try FileSafety.restore(record))
        XCTAssertEqual(try String(contentsOf: source), "keep")
        XCTAssertEqual(try String(contentsOf: dest), "moved")
    }
    func testUndoRefusesChangedIdentity() throws {
        let dest = root.appendingPathComponent("moved")
        try Data([1]).write(to: dest)
        let record = MoveRecord(source: root.appendingPathComponent("original"), destination: dest, identity: "wrong", reason: "Test")
        XCTAssertThrowsError(try FileSafety.restore(record))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }
    func testOrganizerExcludesSymbolicLinks() throws {
        let file = root.appendingPathComponent("real.txt")
        let link = root.appendingPathComponent("alias.txt")
        try Data([1]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertTrue(FileSafety.regular(file))
        XCTAssertFalse(FileSafety.regular(link))
        XCTAssertEqual(FileSafety.category(root.appendingPathComponent("PHOTO.JPG")), "Images")
        XCTAssertEqual(FileSafety.category(root.appendingPathComponent("app.dmg")), "Installers")
    }
    func testExportResizesAndNeverOverwrites() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let source = root.appendingPathComponent("source.png")
        let output = root.appendingPathComponent("out.jpg")
        let original = bitmap.representation(using: .png, properties: [:])!
        try original.write(to: source)
        try ImageExporter.export(source, to: output, options: ImageExportOptions(jpeg: true, quality: 0.8, maxPixels: 40, prefix: ""))
        let image = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as! [CFString: Any]
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 20)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        XCTAssertThrowsError(try ImageExporter.export(source, to: output, options: ImageExportOptions()))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testBatchNaming() {
        XCTAssertEqual(ImageExporter.name(source: URL(fileURLWithPath: "/a/photo.png"), index: 2, options: ImageExportOptions(prefix: "trip")), "trip-003.png")
    }
}
