import SwiftUI

/// Files downloaded from web pages: open or share them, or delete them.
struct DownloadsView: View {
    @Environment(Downloads.self) var downloads

    var body: some View {
        List {
            if !downloads.inProgress.isEmpty {
                Section("Downloading") {
                    ForEach(downloads.inProgress) { download in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(download.name).lineLimit(1)
                            if let progress = download.progress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                }
            }
            Section {
                if downloads.files.isEmpty {
                    Text("Nothing downloaded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloads.files) { file in
                    row(file)
                }
            }
        }
        .navigationTitle("Downloads")
        .onAppear { downloads.reload() }
    }

    private func row(_ file: Downloads.File) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .accessibilityIdentifier("downloadName")
                Text(Self.sizeText(file.size))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            #if os(Android)
            Button { downloads.open(file) } label: {
                Image(systemName: "arrow.forward.square").frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Open"))
            #else
            // The share sheet opens it in another app or saves it elsewhere.
            ShareLink(item: file.url) {
                Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Share"))
            #endif
            Button { downloads.delete(file) } label: {
                Image(systemName: "trash").frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Delete"))
        }
        .buttonStyle(.borderless)
    }

    static func sizeText(_ bytes: Int) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unit = 0
        while size >= 1000 && unit < units.count - 1 {
            size /= 1000
            unit += 1
        }
        return unit == 0 ? "\(bytes) bytes" : "\(String(format: "%.1f", size)) \(units[unit])"
    }
}
