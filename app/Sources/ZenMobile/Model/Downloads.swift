import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse

/// Files downloaded from web pages, kept in the app's Downloads folder
/// (on iOS it's in Documents, so the Files app shows it too).
@MainActor @Observable final class Downloads {
    struct File: Identifiable {
        let url: URL
        let size: Int
        let date: Date

        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// A download in progress.
    struct Active: Identifiable {
        let name: String
        /// From 0 to 1; nil when the size isn't known.
        var progress: Double?

        var id: String { name }
    }

    let directory: URL
    private(set) var files: [File] = []
    private(set) var inProgress: [Active] = []

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    /// The folder downloads go to on this platform.
    static func defaultDirectory() -> URL {
        #if os(Android)
        // Where Android's file provider can share files from (see
        // GeckoDownloads.kt and res/xml/zen_file_paths.xml).
        URL(fileURLWithPath: AndroidFiles.downloadsDirectory())
        #else
        URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        #endif
    }

    /// A free file in the folder for `suggestedName`: report.pdf, then
    /// report (1).pdf, and so on.
    func destination(for suggestedName: String) -> URL {
        var name = suggestedName.replacingOccurrences(of: "/", with: "_")
        if name.isEmpty || name.hasPrefix(".") {
            name = "download" + name
        }
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var count = 1
        while FileManager.default.fileExists(atPath: candidate.path) || isActive(candidate.lastPathComponent) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) (\(count))" : "\(base) (\(count)).\(ext)")
            count += 1
        }
        return candidate
    }

    func started(_ name: String) {
        inProgress.append(Active(name: name))
    }

    func update(_ name: String, progress: Double) {
        if let index = inProgress.firstIndex(where: { $0.name == name }) {
            inProgress[index].progress = progress
        }
    }

    func finished(_ name: String) {
        inProgress.removeAll { $0.name == name }
        reload()
    }

    private func isActive(_ name: String) -> Bool {
        inProgress.contains { $0.name == name }
    }

    func delete(_ file: File) {
        try? FileManager.default.removeItem(at: file.url)
        reload()
    }

    func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        files = urls
            .filter { !isActive($0.lastPathComponent) }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return File(url: url, size: values?.fileSize ?? 0, date: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }

    /// Opens a downloaded file in another app (Android; iOS uses the share
    /// sheet).
    func open(_ file: File) {
        #if os(Android)
        AndroidFiles.open(path: file.url.path)
        #endif
    }
}
