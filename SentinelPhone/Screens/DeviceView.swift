import SwiftUI
import UIKit

enum SettingsRoute: Hashable {
    case lan
    case relay
    case preview
    case recording
    case storage
    case detection
    case deviceInfo
    case cameras
    case actions

    var title: String {
        switch self {
        case .lan: return "局域网直连"
        case .relay: return "远程中继"
        case .preview: return "预览画面"
        case .recording: return "录制"
        case .storage: return "存储"
        case .detection: return "侦测"
        case .deviceInfo: return "车机信息"
        case .cameras: return "摄像头"
        case .actions: return "快捷操作"
        }
    }
}

struct DeviceView: View {

    @EnvironmentObject private var store: SentinelStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppTopBar(title: "设置") {
                    HStack(spacing: 10) {
                        BreathingDot(on: store.isConnected)
                        TopBarIconButtons(systemIcon: "arrow.clockwise") {
                            store.refreshNow()
                        }
                    }
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let error = store.lastError, !error.isEmpty {
                            AuroraBanner(
                                systemIcon: "exclamationmark.triangle.fill",
                                text: error,
                                tone: Aurora.rose
                            )
                        }

                        connectionGroup
                        previewGroup
                        recordingGroup
                        storageGroup
                        deviceGroup
                    }
                    .padding(.horizontal, AuroraMetrics.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 126)
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                SettingsDetailView(route: route)
            }
        }
    }

    // MARK: - 分组

    private var connectionGroup: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsNavigationRow(
                    route: .lan,
                    title: "局域网直连",
                    icon: "wifi",
                    tone: Aurora.brand,
                    status: store.mode == .lan && store.isConnected
                )
                SettingsDivider()
                SettingsNavigationRow(
                    route: .relay,
                    title: "远程中继",
                    icon: "antenna.radiowaves.left.and.right",
                    tone: Aurora.rose,
                    status: store.mode == .relay && store.isConnected
                )
            }
        }
    }

    private var previewGroup: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsNavigationRow(
                    route: .preview,
                    title: "预览画面",
                    icon: "video",
                    tone: Aurora.teal,
                    value: "\(store.liveFps) fps · \(store.liveWidth)px"
                )
            }
        }
    }

    private var recordingGroup: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsNavigationRow(
                    route: .recording,
                    title: "录制",
                    icon: "record.circle",
                    tone: Aurora.rose,
                    value: "\(store.recordFps) fps · \(store.recordWidth)px"
                )
            }
        }
    }

    private var storageGroup: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsNavigationRow(
                    route: .storage,
                    title: "存储",
                    icon: "internaldrive",
                    tone: Aurora.warning,
                    value: "\(store.retentionDays) 天"
                )
                SettingsDivider()
                SettingsNavigationRow(
                    route: .detection,
                    title: "侦测",
                    icon: "figure.walk.motion",
                    tone: Aurora.brand,
                    status: store.motionEnabled
                )
            }
        }
    }

    private var deviceGroup: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsNavigationRow(
                    route: .deviceInfo,
                    title: "车机信息",
                    icon: "car.fill",
                    tone: Aurora.info,
                    status: store.isConnected
                )
                SettingsDivider()
                SettingsNavigationRow(
                    route: .cameras,
                    title: "摄像头",
                    icon: "video.fill",
                    tone: Aurora.teal,
                    value: "\(store.status?.onlineCount ?? 0)/\(store.status?.totalCount ?? 0)"
                )
                SettingsDivider()
                SettingsNavigationRow(
                    route: .actions,
                    title: "快捷操作",
                    icon: "bolt.fill",
                    tone: Aurora.warning
                )
            }
        }
    }
}

// MARK: - 二级页

struct SettingsDetailView: View {

    let route: SettingsRoute
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SentinelStore

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: route.title)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    switch route {
                    case .lan: lanPage
                    case .relay: relayPage
                    case .preview: previewPage
                    case .recording: recordingPage
                    case .storage: storagePage
                    case .detection: detectionPage
                    case .deviceInfo: deviceInfoPage
                    case .cameras: camerasPage
                    case .actions: actionsPage
                    }
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 2)
                .padding(.bottom, 126)
            }
        }
    }

    // MARK: - 局域网

    private var lanPage: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "局域网直连",
                    systemIcon: "wifi",
                    tone: Aurora.brand,
                    trailingText: store.mode == .lan ? store.connection.title : "未使用"
                )

                HStack(spacing: 6) {
                    StatusPill(text: store.mode == .lan ? store.connection.title : "未使用", color: connectionTone)
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
                    GlassActionButton(
                        text: store.mode == .lan && store.isConnected ? "重新连接" : "连接车机",
                        systemIcon: "link",
                        prominent: true,
                        enabled: !store.isBusy
                    ) {
                        store.connectLAN()
                    }
                    GlassActionButton(
                        text: store.mode == .lan && store.isConnected ? "断开" : "扫描",
                        systemIcon: store.mode == .lan && store.isConnected ? "xmark" : "dot.radiowaves.left.and.right"
                    ) {
                        if store.mode == .lan && store.isConnected {
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
                    }
                } else if !(store.mode == .lan && store.isConnected) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("正在搜索 _carsentinel._tcp / UDP 8721 …")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                }
            }
        }
    }

    // MARK: - 中继

    private var relayPage: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "远程中继",
                    systemIcon: "antenna.radiowaves.left.and.right",
                    tone: Aurora.rose,
                    trailingText: store.mode == .relay ? store.connection.title : "未使用"
                )

                HStack(spacing: 6) {
                    StatusPill(text: store.mode == .relay ? store.connection.title : "未使用", color: connectionTone)
                    if store.relayDevices.contains(where: { $0.id == store.relayDeviceID }) {
                        Text(store.relayDeviceID)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                AuroraTextField(
                    placeholder: "中继地址，例如 wss://relay.example.com",
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
                    GlassActionButton(
                        text: store.mode == .relay && store.isConnected ? "重新连接" : "连接中继",
                        systemIcon: "antenna.radiowaves.left.and.right",
                        prominent: true,
                        enabled: !store.isBusy
                    ) {
                        store.connectRelay()
                    }
                    GlassActionButton(
                        text: store.mode == .relay && store.isConnected ? "断开" : "获取设备",
                        systemIcon: store.mode == .relay && store.isConnected ? "xmark" : "arrow.down.circle"
                    ) {
                        if store.mode == .relay && store.isConnected {
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
                            let selected = store.relayDeviceID == device.id
                            Button {
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
                    }
                }
            }
        }
    }

    // MARK: - 预览

    private var previewPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "预览帧率",
                        systemIcon: "speedometer",
                        tone: Aurora.teal,
                        trailingText: "\(store.liveFps) fps"
                    )
                    choiceRow(options: [30, 36, 40, 48, 50, 60], current: store.liveFps) { value in
                        store.updateConfig(["liveFps": value])
                    } label: { value in
                        "\(value) fps"
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "画面清晰度",
                        systemIcon: "rectangle.compress.vertical",
                        tone: Aurora.brand,
                        trailingText: "\(store.liveWidth) px"
                    )
                    choiceRow(options: [320, 480, 640, 960, 1280], current: store.liveWidth) { value in
                        store.updateConfig(["liveWidth": value])
                    } label: { value in
                        "\(value) px"
                    }
                }
            }
        }
    }

    // MARK: - 录制

    private var recordingPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "录制帧率",
                        systemIcon: "speedometer",
                        tone: Aurora.rose,
                        trailingText: "\(store.recordFps) fps"
                    )
                    choiceRow(options: [30, 40, 50, 60], current: store.recordFps) { value in
                        store.updateConfig(["recordFps": value])
                    } label: { value in
                        "\(value) fps"
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "录制清晰度",
                        systemIcon: "rectangle.compress.vertical",
                        tone: Aurora.teal,
                        trailingText: "\(store.recordWidth) px"
                    )
                    choiceRow(options: [480, 640, 960, 1280], current: store.recordWidth) { value in
                        store.updateConfig(["recordWidth": value])
                    } label: { value in
                        "\(value) px"
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "录制画质",
                        systemIcon: "camera.fill",
                        tone: Aurora.brand,
                        trailingText: "\(store.recordQuality)%"
                    )
                    choiceRow(options: [40, 55, 62, 75, 90], current: store.recordQuality) { value in
                        store.updateConfig(["recordQuality": value])
                    } label: { value in
                        "\(value)%"
                    }
                }
            }

            SectionCard {
                Toggle(isOn: Binding(get: { store.autoRecord }, set: { store.setAutoRecord($0) })) {
                    Text("自动开始录制")
                        .font(AuroraFont.labelLarge)
                        .foregroundStyle(Aurora.ink)
                }
            }
        }
    }

    // MARK: - 存储

    private var storagePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    AuroraSectionHeader(
                        title: "存储",
                        systemIcon: "internaldrive.fill",
                        tone: Aurora.warning,
                        trailingText: "\(store.status?.freeText ?? "—") 可用"
                    )
                    StorageProgress(
                        used: store.status?.storage?.recordBytes ?? 0,
                        total: store.status?.storage?.totalBytes ?? 0
                    )
                    Divider().background(Aurora.line.opacity(0.6))
                    Text("保留天数")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                    HStack(spacing: 7) {
                        ForEach([1, 3, 7, 30], id: \.self) { days in
                            FilterChip(text: "\(days) 天", selected: store.retentionDays == days) {
                                store.updateConfig(["retentionDays": days])
                            }
                        }
                    }
                    GlassActionButton(
                        text: "立即清理过期录像",
                        systemIcon: "trash",
                        enabled: !store.isBusy,
                        height: 46
                    ) {
                        store.control("cleanup")
                    }
                }
            }
        }
    }

    // MARK: - 侦测

    private var detectionPage: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { store.motionEnabled }, set: { store.updateConfig(["motionEnabled": $0]) })) {
                    Text("移动侦测")
                        .font(AuroraFont.labelLarge)
                        .foregroundStyle(Aurora.ink)
                }
                

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("灵敏度")
                            .font(AuroraFont.labelMedium)
                            .foregroundStyle(Aurora.inkSoft)
                        Spacer()
                        Text("\(Int((store.motionSensitivity * 100).rounded()))%")
                            .font(AuroraFont.labelMedium)
                            .foregroundStyle(Aurora.brandDeep)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(store.motionSensitivity) },
                            set: { store.updateConfig(["motionSensitivity": $0]) }
                        ),
                        in: 0.02...0.30
                    )
                }

                Divider().background(Aurora.line.opacity(0.6))

                Toggle(isOn: Binding(get: { store.shockEnabled }, set: { store.updateConfig(["shockEnabled": $0]) })) {
                    Text("车辆震动")
                        .font(AuroraFont.labelLarge)
                        .foregroundStyle(Aurora.ink)
                }
            }
        }
    }

    // MARK: - 车机信息

    @ViewBuilder
    private var deviceInfoPage: some View {
        if let status = store.status, !store.isDemo {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "车机信息",
                        systemIcon: "car.fill",
                        tone: Aurora.teal,
                        trailingText: store.isConnected ? "在线" : "离线"
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
        } else {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("还没有设备状态")
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text("连接车机后，这里会显示型号、网络和运行状态。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                }
            }
        }
    }

    // MARK: - 摄像头

    @ViewBuilder
    private var camerasPage: some View {
        if let status = store.status, !status.channelsOrEmpty.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    AuroraSectionHeader(
                        title: "摄像头",
                        systemIcon: "video.fill",
                        tone: Aurora.brand,
                        trailingText: "\(status.onlineCount)/\(status.totalCount) 在线"
                    )
                    Divider().background(Aurora.line.opacity(0.6))
                    ForEach(status.channelsOrEmpty) { channel in
                        HStack(spacing: 9) {
                            BreathingDot(on: channel.isOnline, size: 7)
                            Text(channel.displayName)
                                .font(AuroraFont.labelMedium)
                                .foregroundStyle(Aurora.ink)
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
        } else {
            SectionCard {
                Text("还没有配置机位")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.muted)
            }
        }
    }

    // MARK: - 快捷操作

    private var actionsPage: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "快捷操作",
                    systemIcon: "bolt.fill",
                    tone: Aurora.warning
                )
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

    // MARK: - 组件

    private var connectionTone: Color {
        switch store.connection {
        case .demo: return Aurora.warning
        case .connecting: return Aurora.warning
        case .connected: return Aurora.teal
        case .failed: return Aurora.rose
        case .idle: return Aurora.muted
        }
    }

    private func choiceRow(
        options: [Int],
        current: Int,
        onSelect: @escaping (Int) -> Void,
        label: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(label(option))
                            .font(AuroraFont.bodyLarge)
                            .foregroundStyle(option == current ? Aurora.brandDeep : Aurora.ink)
                        Spacer()
                        if option == current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Aurora.brand)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(option == current ? Aurora.brand.tint(0.10) : Aurora.surfaceVariant.opacity(0.45))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
                if option != options.last {
                    Spacer(minLength: 6)
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
            .auroraGlassSurface(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                tone: Aurora.inkSoft,
                tint: 0,
                border: 0.18,
                shadowRadius: 2,
                shadowY: 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(store.isBusy)
        .opacity(store.isBusy ? 0.55 : 1)
    }
}

// MARK: - 行组件

struct SettingsNavigationRow: View {
    let route: SettingsRoute
    let title: String
    var icon: String
    var tone: Color = Aurora.brand
    var value: String? = nil
    /// 连接状态呼吸灯：true 绿 / false 红 / nil 不显示
    var status: Bool? = nil

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.tint(0.13))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tone)
                    )
                Text(title)
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let status {
                    BreathingDot(on: status)
                }
                if let value {
                    Text(value)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Aurora.muted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().background(Aurora.line.opacity(0.5))
    }
}
