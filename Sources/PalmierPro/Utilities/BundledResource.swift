import Foundation

private final class BundledResourceToken {}

enum BundledResource {
    private static let resourceBundleName = "PalmierPro_PalmierPro.bundle"

    static let bundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return .main }
        let buildDirectory = Bundle(for: BundledResourceToken.self).bundleURL.deletingLastPathComponent()
        let resourceBundleURL = buildDirectory.appendingPathComponent(resourceBundleName)
        return Bundle(url: resourceBundleURL) ?? .main
    }()

    /// Lookup order: the packaged app's flattened Resources, then SwiftPM's resource bundle for `swift run` and tests.
    private static let roots: [URL] = {
        let buildDirectory = Bundle(for: BundledResourceToken.self).bundleURL.deletingLastPathComponent()
        let resourceBundles = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            buildDirectory.appendingPathComponent(resourceBundleName),
        ]
        return ([Bundle.main.resourceURL] + resourceBundles.map { $0.flatMap(resourceDirectory(ofBundleAt:)) })
            .compactMap { $0 }
    }()

    static func url(_ path: String) -> URL? {
        roots.lazy
            .map { $0.appendingPathComponent(path) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// SwiftPM emits a flat bundle on older toolchains and a macOS-style `Contents/Resources` bundle on newer ones.
    static func resourceDirectory(ofBundleAt url: URL) -> URL? {
        Bundle(url: url)?.resourceURL
    }
}
