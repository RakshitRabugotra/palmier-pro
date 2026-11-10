import Foundation
import Testing
@testable import PalmierPro

@Suite("BundledResource")
struct BundledResourceTests {

    @Test(arguments: [
        "Fonts",
        "Images/welcome-butterfly.jpg",
        "Changelog/changelog.json",
        "Models/BeatThis.mlmodelc",
        "Vignette.metallib",
    ])
    func resolvesBundledResourceUnderSwiftPM(path: String) {
        #expect(BundledResource.url(path) != nil)
    }

    @Test func missingResourceResolvesToNil() {
        #expect(BundledResource.url("Definitely/Not/Here.bin") == nil)
    }

    @Test func flatBundleResourcesLiveAtTheBundleRoot() throws {
        let bundle = try makeTemporaryBundle(contentsLayout: false)
        defer { try? FileManager.default.removeItem(at: bundle) }
        #expect(BundledResource.resourceDirectory(ofBundleAt: bundle)?.standardizedFileURL == bundle.standardizedFileURL)
    }

    @Test func contentsLayoutBundleResourcesLiveInContentsResources() throws {
        let bundle = try makeTemporaryBundle(contentsLayout: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let expected = bundle.appendingPathComponent("Contents/Resources").standardizedFileURL
        #expect(BundledResource.resourceDirectory(ofBundleAt: bundle)?.standardizedFileURL == expected)
    }

    private func makeTemporaryBundle(contentsLayout: Bool) throws -> URL {
        let fm = FileManager.default
        let bundle = fm.temporaryDirectory.appendingPathComponent("BundledResourceTests-\(UUID().uuidString).bundle")
        let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.bundle</string></dict></plist>"#
        if contentsLayout {
            try fm.createDirectory(at: bundle.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
            try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        } else {
            try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
            try plist.write(to: bundle.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        }
        return bundle
    }
}
