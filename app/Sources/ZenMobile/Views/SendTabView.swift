import SwiftUI
import ZenCore

/// Sends the page to another of the account's devices.
struct SendTabView: View {
    @Environment(AppModel.self) var app
    @Environment(\.dismiss) var dismiss
    let url: URL
    let title: String
    @State var sending: String?
    @State var failed = false

    var body: some View {
        NavigationStack {
            List {
                if app.sendTabDevices.isEmpty {
                    Text("No other devices can receive tabs. Sign in to Firefox or Zen on your computer with the same account.")
                        .foregroundStyle(.secondary)
                }
                ForEach(app.sendTabDevices, id: \.id) { device in
                    Button {
                        send(to: device)
                    } label: {
                        HStack {
                            ZenSymbolImage(symbol: .desktop, size: 20)
                            Text(device.displayName)
                            Spacer()
                            if sending == device.id {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(sending != nil)
                    .accessibilityIdentifier("sendTabDevice")
                }
                if failed {
                    Text("Couldn't send the tab. Check your connection and try again.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Send to device")
            .task { await app.refreshDevices() }
        }
        .presentationDetents([.medium])
    }

    private func send(to device: Device) {
        sending = device.id
        failed = false
        Task {
            let sent = await app.sendTab(url, title: title, to: device)
            sending = nil
            if sent {
                dismiss()
            } else {
                failed = true
            }
        }
    }
}
