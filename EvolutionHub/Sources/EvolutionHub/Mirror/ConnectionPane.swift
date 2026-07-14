import AppKit
import EvolutionCore
import EvolutionHubCore
import SwiftUI
import UniformTypeIdentifiers

struct ConnectionPane: View {
    @EnvironmentObject private var mirror: MirrorSessionController
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("镜像连接")
                    .font(.largeTitle.weight(.semibold))

                statusCard

                Text("Mac 不能独立记账。用局域网配对（推荐）或导入 SyncEnvelope 建立镜像；之后「今天」操作会同步回手机。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                lanSection
                fileSection

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(mirror.canBookkeep ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(mirror.canBookkeep ? "已连接 · 可记账（镜像）" : "未连接 · 记账已锁定")
                    .font(.title3.weight(.medium))
            }
            Text(mirror.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if mirror.networkHost.isAdvertising {
                Text("配对码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(mirror.networkHost.pairingCode)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            if mirror.canBookkeep {
                Text("未记录 \(formatDuration(mirror.unclassifiedDuration))")
                    .font(.title2.monospacedDigit())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var lanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("局域网自动镜像（推荐）")
                .font(.headline)
            Text("1. Mac 点「开始等待 iPhone」  2. 手机设置 → 连接 Mac 镜像 → 输入配对码")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if mirror.networkHost.isAdvertising {
                    Button("停止广播") { mirror.stopLANAdvertising() }
                } else {
                    Button("开始等待 iPhone") { mirror.startLANAdvertising() }
                        .buttonStyle(.borderedProminent)
                }
                Button("请求手机刷新") { mirror.requestPhoneRefresh() }
                    .disabled(!mirror.networkHost.isPeerConnected)
                Button("断开连接", role: .destructive) { mirror.disconnect() }
            }
            if mirror.networkHost.isPeerConnected {
                Text("手机链路：已连接")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文件连接（备用）")
                .font(.headline)
            HStack {
                Button("从 SyncEnvelope 连接…") { importSyncBatch() }
                    .disabled(mirror.canBookkeep)
                Button("从镜像快照连接…") { importSnapshot() }
                    .disabled(mirror.canBookkeep)
            }
            TextField("同步目录（可选）", text: $mirror.syncFolderPath)
            HStack {
                Button("从同步目录拉取") {
                    do { try mirror.pullInboundFromSyncFolder() }
                    catch { errorText = error.localizedDescription }
                }
                .disabled(!mirror.canBookkeep)
                Button("导出回写批次…") { exportOutbound() }
                    .disabled(!mirror.canBookkeep)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func importSyncBatch() {
        pickJSON { url in
            do {
                try mirror.connectFromSyncBatchFile(url: url)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func importSnapshot() {
        pickJSON { url in
            do {
                try mirror.connectFromSnapshotFile(url: url)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func exportOutbound() {
        do {
            let url = try mirror.exportOutboundBatch()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func pickJSON(_ handle: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            handle(url)
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
