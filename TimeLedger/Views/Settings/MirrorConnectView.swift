import SwiftData
import SwiftUI

struct MirrorConnectView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var client = MirrorNetworkPhoneClient()
    @State private var pairingCode = ""

    var body: some View {
        Form {
            Section {
                Text(client.status)
                    .foregroundStyle(client.isConnected ? .green : .secondary)
                if let name = client.discoveredName {
                    Text("发现：\(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("状态")
            }

            Section {
                TextField("Mac 配对码（6 位）", text: $pairingCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                Button(client.isConnected || client.isBrowsing ? "断开" : "连接 Mac") {
                    if client.isConnected || client.isBrowsing {
                        client.stop()
                    } else {
                        client.connect(pairingCode: pairingCode, modelContext: modelContext)
                    }
                }
                .disabled(!client.isConnected && !client.isBrowsing && pairingCode.count < 4)

                Button("立即推送全量到 Mac") {
                    client.pushFullSnapshot()
                }
                .disabled(!client.isConnected)
            } header: {
                Text("局域网镜像")
            } footer: {
                Text("先在 Mac「连接 iPhone」点开始等待，再输入配对码。同一 Wi‑Fi。连接后手机记账会推送镜像；Mac 改账会回写到本机。")
            }
        }
        .navigationTitle("连接 Mac 镜像")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // keep connection when leaving page
        }
    }
}
