import SwiftUI
import UIKit

struct DeviceView: View {

    @EnvironmentObject private var store: SentinelStore

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "设备", subtitle: subtitle) {
                TopBarIconButtons(systemIcon: "arrow.clockwise") {
                    store.refreshNow()
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    modeSelector

                    if let error = store.lastError, !error.isEmpty {
                        AuroraBanner(
                            systemIcon: "exclamationmark.triangle.fill",
                            text: error,
                            tone: Aurora.rose
                        )
                    }

                    switch store.mode {
                    case .demo, .lan:
                        lanCard
                    case .relay:
                        relayCard
                    }

                    if let status = store.status, !store.isDemo {
                        deviceCard(status)
                        channelCard(status)
                        storageCard(status)
                        actionCard
                    } else if store.mode == .lan || store.mode == .relay {
                        notConnectedCard
                    }

                    aboutCard
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 2)
                .padding(.bottom, 126)
            }
        }
        .onAppear {
            if store.mode == .lan { store.startDiscovery() }
        }
    }

    private var subtitle: String {
        if store.isDemo { return "演示模式 · 局域网 / 远程中继" }
        return "\(store.deviceName) · \(store.mode.title)"
    }

    // MARK: - 模式

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach([ConnectionMode.lan, .relay], id: \.self) { mode in
                let selected = store.mode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        store.setMode(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Aurora.brandDeep : Aurora.inkSoft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(selected ? Aurora.brand.tint(0.13) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Aurora.surface)
                .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Aurora.line.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - 演示

    private var demoCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Aurora.brand.tint(0.14))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("演示模式")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text("没有连接车机时，先看看完整界面")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                    Spacer()
                    StatusPill(text: "演示数据", color: Aurora.warning)
                }

                Text("连接后，实时画面、回放和事件都会切换成车机的真实数据。建议先在同一个 Wi-Fi 下用局域网直连。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    BrandButton(text: "局域网连接", systemIcon: "wifi") {
                        store.setMode(.lan)
                    }
                    SmallTonalButton(
                        text: "远程中继",
                        systemIcon: "antenna.radiowaves.left.and.right",
                        expands: true,
                        height: 44
                    ) {
                        store.setMode(.relay)
                    }
                }
            }
        }
    }

    // MARK: - 局域网

    private var lanCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "局域网直连",
                    subtitle: "同一 Wi-Fi 下自动发现车机",
                    systemIcon: "wifi",
                    tone: Aurora.brand,
                    trailingText: lanStateText
                )

                HStack(spacing: 6) {
                    StatusPill(text: connectionText, color: connectionTone)
                    if store.isConnected {
                        Text(store.lanAddress)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                AuroraTextField(
                    placeholder: "车机地址，例如 192.168.1.23:8720",
                    text: $store.lanAddress,
                    systemIcon: "number",
                    keyboardType: .numbersAndPunctuation
                )

                HStack(spacing: 8) {
                    BrandButton(
                        text: store.isConnected ? "重新连接" : "连接车机",
                        systemIcon: "link",
                        enabled: !store.isBusy
                    ) {
                        store.connectLAN()
                    }
                    SmallTonalButton(
                        text: store.isConnected ? "断开" : "扫描",
                        systemIcon: store.isConnected ? "xmark" : "dot.radiowaves.left.and.right",
                        expands: true,
                        height: 44
                    ) {
                        if store.isConnected {
                            store.disconnect()
                        } else {
                            store.startDiscovery()
                        }
                    }
                }

                if !store.discoveries.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("附近的车辆")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                        ForEach(store.discoveries) { device in
                            discoveryRow(device)
                        }
                    }
                } else if !store.isConnected {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在搜索 _carsentinel._tcp …")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                    .padding(.top, 1)
                }

                Text("首次连接会弹出「本地网络」权限，请选择允许。")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    private func discoveryRow(_ device: DiscoveredDevice) -> some View {
        Button {
            store.lanAddress = device.urlText
            store.connectLAN(address: device.urlText)
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Aurora.teal.tint(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "car.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Aurora.teal)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(AuroraFont.labelMedium)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(device.urlText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text("连接")
                    .font(AuroraFont.labelMedium)
                    .foregroundStyle(Aurora.brand)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Aurora.surfaceVariant.opacity(0.55))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - 中继

    private var relayCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "远程中继",
                    subtitle: "跨网络时，车机主动连出到中继",
                    systemIcon: "antenna.radiowaves.left.and.right",
                    tone: Aurora.rose,
                    trailingText: relayStateText
                )

                HStack(spacing: 6) {
                    StatusPill(text: connectionText, color: connectionTone)
                    if store.relayDevices.contains(where: { $0.id == store.relayDeviceID }) {
                        Text(store.relayDeviceID)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                AuroraTextField(
                    placeholder: "中继地址，例如 wss://relay.example.com/ws",
                    text: $store.relayURL,
                    systemIcon: "link",
                    keyboardType: .URL
                )

                AuroraTextField(
                    placeholder: "访问密钥（可选）",
                    text: $store.relayKey,
                    systemIcon: "key.fill",
                    isSecure: true
                )

                AuroraTextField(
                    placeholder: "车机 ID（可从设备列表里选）",
                    text: $store.relayDeviceID,
                    systemIcon: "car.fill",
                    keyboardType: .asciiCapable
                )

                HStack(spacing: 8) {
                    BrandButton(
                        text: store.isConnected ? "重新连接" : "连接中继",
                        systemIcon: "antenna.radiowaves.left.and.right",
                        enabled: !store.isBusy
                    ) {
                        store.connectRelay()
                    }
                    SmallTonalButton(
                        text: store.isConnected ? "断开" : "获取设备",
                        systemIcon: store.isConnected ? "xmark" : "arrow.down.circle",
                        expands: true,
                        height: 44
                    ) {
                        if store.isConnected {
                            store.disconnect()
                        } else {
                            store.loadRelayDevices()
                        }
                    }
                }

                if store.relayLoading {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("正在读取中继设备列表…")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                } else if !store.relayDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("中继上的车机")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                        ForEach(store.relayDevices) { device in
                            relayDeviceRow(device)
                        }
                    }
                }

                Text("中继只转发加密 WebSocket 流量；车机端不需要公网 IP。")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    private func relayDeviceRow(_ device: RelayDevice) -> some View {
        let selected = store.relayDeviceID == device.id
        return Button {
            store.relayDeviceID = device.id
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(device.isOnline ? Aurora.teal : Aurora.muted)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .font(AuroraFont.labelMedium)
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                    Text(device.id)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text(device.isOnline ? "在线" : "离线")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(device.isOnline ? Aurora.teal : Aurora.muted)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Aurora.brand.tint(0.10) : Aurora.surfaceVariant.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Aurora.brand.opacity(0.20) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - 设备信息

    private func deviceCard(_ status: SentinelStatus) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "车机信息",
                    subtitle: [status.device?.model, status.device?.version].compactMap { $0 }.joined(separator: " · "),
                    systemIcon: "car.fill",
                    tone: Aurora.teal,
                    trailingText: store.connection.isConnected ? "在线" : "演示"
                )
                Divider().background(Aurora.line.opacity(0.6))
                InfoRow(label: "设备名称", value: status.deviceName, systemIcon: "tag")
                InfoRow(label: "设备 ID", value: status.device?.id ?? "—", systemIcon: "number")
                InfoRow(label: "局域网", value: status.network?.lanUrl ?? "—", systemIcon: "wifi")
                InfoRow(label: "运行时间", value: status.uptimeText, systemIcon: "clock")
                InfoRow(
                    label: "远程中继",
                    value: (status.relay?.connected ?? false) ? "已连接" : ((status.relay?.enabled ?? false) ? "已启用" : "未启用"),
                    valueColor: (status.relay?.connected ?? false) ? Aurora.teal : Aurora.inkSoft,
                    systemIcon: "antenna.radiowaves.left.and.right"
                )
            }
        }
    }

    private func channelCard(_ status: SentinelStatus) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "摄像头",
                    subtitle: "实时采集与录制状态",
                    systemIcon: "video.fill",
                    tone: Aurora.brand,
                    trailingText: "\(status.onlineCount)/\(status.totalCount) 在线"
                )
                Divider().background(Aurora.line.opacity(0.6))
                if status.channelsOrEmpty.isEmpty {
                    Text("还没有配置机位")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.muted)
                } else {
                    ForEach(status.channelsOrEmpty) { channel in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(channel.isOnline ? Aurora.teal : Aurora.muted)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(channel.displayName)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(Aurora.ink)
                                Text(channel.sourceLabel ?? channel.source ?? "摄像头")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Aurora.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(channel.displayResolution)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Aurora.inkSoft)
                                Text(channel.isOnline ? "\(channel.displayFPS) fps" : "离线")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(channel.isOnline ? Aurora.muted : Aurora.warning)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func storageCard(_ status: SentinelStatus) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "存储",
                    subtitle: "循环覆盖 · 保留 \(status.retentionText)",
                    systemIcon: "internaldrive.fill",
                    tone: Aurora.rose,
                    trailingText: "\(status.freeText) 可用"
                )
                StorageProgress(
                    used: status.storage?.recordBytes ?? 0,
                    total: status.storage?.totalBytes ?? 0
                )
                HStack {
                    Text("录像 \(status.recordText)")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer()
                    Text("共 \(formatBytes(status.storage?.totalBytes ?? 0))")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }
                HStack(spacing: 6) {
                    TinyTag(text: "保留 \(status.retentionText)", systemIcon: "calendar", tone: Aurora.brand)
                    TinyTag(text: "\(status.metrics?.recordFps ?? 2) fps", systemIcon: "speedometer", tone: Aurora.teal)
                    TinyTag(text: "640 px", systemIcon: "rectangle.compress.vertical", tone: Aurora.rose)
                }
            }
        }
    }

    private var actionCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "快捷操作",
                    subtitle: "抓拍、重启机位、清理旧录像",
                    systemIcon: "bolt.fill",
                    tone: Aurora.warning
                )
                Toggle(isOn: Binding(get: { store.autoRecord }, set: { store.setAutoRecord($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动开始录制")
                            .font(AuroraFont.labelLarge)
                            .foregroundStyle(Aurora.ink)
                        Text("车机服务启动后立即开始录像")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                }
                .tint(Aurora.brand)
                Divider().background(Aurora.line.opacity(0.6))
                HStack(spacing: 8) {
                    actionButton("抓拍", icon: "camera.fill", tone: Aurora.brand) {
                        store.control("snapshot")
                    }
                    actionButton("重启机位", icon: "arrow.triangle.2.circlepath", tone: Aurora.teal) {
                        store.control("restart_channels")
                    }
                    actionButton("清理", icon: "trash", tone: Aurora.rose) {
                        store.control("cleanup")
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Aurora.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone.tint(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tone.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(store.isBusy)
        .opacity(store.isBusy ? 0.55 : 1)
    }

    private var notConnectedCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("还没有设备状态")
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                Text("连接成功后，这里会显示车机型号、摄像头离线情况、存储空间和远程中继状态。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if store.mode == .lan {
                    SmallTonalButton(text: "重新搜索局域网设备", systemIcon: "dot.radiowaves.left.and.right", expands: true, height: 40) {
                        store.startDiscovery()
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Monogram(name: "哨", tone: Aurora.brand, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("车载哨兵")
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                        Text("Android 车机端 · iOS 手机端")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                }
                Text("实时画面走局域网 MJPEG；跨网络时走 WebSocket 中继。回放使用按轮次保存的 JPEG 序列，不依赖 MP4。")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Aurora.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 文案

    private var connectionText: String {
        switch store.connection {
        case .demo: return "演示数据"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        case .idle: return "未连接"
        }
    }

    private var connectionTone: Color {
        switch store.connection {
        case .demo: return Aurora.warning
        case .connecting: return Aurora.warning
        case .connected: return Aurora.teal
        case .failed: return Aurora.rose
        case .idle: return Aurora.muted
        }
    }

    private var lanStateText: String {
        if store.isConnected, store.mode == .lan { return "已连接" }
        if store.discoveries.isEmpty { return "搜索中" }
        return "\(store.discoveries.count) 台"
    }

    private var relayStateText: String {
        if store.isConnected, store.mode == .relay { return "已连接" }
        return store.relayDevices.isEmpty ? "未选择" : "\(store.relayDevices.count) 台"
    }
}
