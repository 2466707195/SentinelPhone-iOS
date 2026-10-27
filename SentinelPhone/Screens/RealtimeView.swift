import SwiftUI

struct RealtimeView: View {

    @EnvironmentObject private var store: SentinelStore
    var onOpenDevices: () -> Void = {}
    @State private var previewChannel: SentinelChannel?

    private var channels: [SentinelChannel] {
        if let channels = store.status?.channels, !channels.isEmpty { return channels }
        return store.isDemo ? DemoData.channels : []
    }

    private var subtitle: String {
        let name = store.deviceName
        guard store.status != nil else { return name }
        return "\(name) · \(store.status?.onlineCount ?? 0)/\(store.status?.totalCount ?? 0) 路在线"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "实时画面", subtitle: subtitle) {
                TopBarIconButtons(
                    systemIcon: "arrow.clockwise",
                    action: { store.refreshNow() },
                    secondarySystemIcon: "slider.horizontal.3",
                    secondaryAction: { onOpenDevices() }
                )
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    statusCard
                    sectionHeader
                    channelGrid
                    hintCard
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 2)
                .padding(.bottom, 124)
            }
            .fullScreenCover(item: $previewChannel) { channel in
                ChannelPreviewView(channel: channel)
                    .environmentObject(store)
            }
        }
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    StatusPill(text: connectionText, color: connectionTone)
                    StatusPill(
                        text: (store.status?.isRecording ?? false) ? "录制中" : "待机",
                        color: (store.status?.isRecording ?? false) ? Aurora.rose : Aurora.muted
                    )
                    Spacer(minLength: 4)
                    Text(durationText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                }

                HStack(spacing: 0) {
                    MetricCell(
                        systemIcon: "dot.radiowaves.left.and.right",
                        label: "总码率",
                        value: store.status?.bitrateText ?? "—",
                        tone: Aurora.brand
                    )
                    verticalDivider
                    MetricCell(
                        systemIcon: "video.fill",
                        label: "在线机位",
                        value: "\(store.status?.onlineCount ?? 0)/\(store.status?.totalCount ?? channels.count)",
                        tone: Aurora.teal
                    )
                    verticalDivider
                    MetricCell(
                        systemIcon: "internaldrive",
                        label: "剩余空间",
                        value: store.status?.freeText ?? "—",
                        tone: Aurora.rose
                    )
                }

                RecordControlButton(isRecording: store.status?.isRecording ?? false) {
                    store.toggleRecording()
                }
                .disabled(store.isBusy)
            }
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Aurora.line.opacity(0.55))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 4)
    }

    // MARK: - 机位

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("全部机位")
                .font(AuroraFont.titleMedium)
                .foregroundStyle(Aurora.ink)
            Text("\(store.status?.onlineCount ?? channels.filter(\.isOnline).count)/\(store.status?.totalCount ?? channels.count)")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.teal)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Aurora.teal.tint(0.12)))
            Spacer()
            Text("2 × 2")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var channelGrid: some View {
        if channels.isEmpty {
            SectionCard {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Aurora.muted)
                    Text("还没有机位")
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text("连接车机后，这里会显示每一路摄像头的实时画面。")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .multilineTextAlignment(.center)
                    SmallTonalButton(text: "去连接车机", systemIcon: "link", expands: true, height: 38) {
                        onOpenDevices()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(channels) { channel in
                    ChannelTile(
                        channel: channel,
                        image: store.frames[channel.id],
                        timestamp: store.frameDates[channel.id],
                        isDemo: store.isDemo,
                        error: store.channelErrors[channel.id]
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        previewChannel = channel
                    }
                }
            }
        }
    }

    // MARK: - 提示卡

    private var hintCard: some View {
        SectionCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [hintTone.tint(0.18), hintTone.tint(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: hintIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(hintTone)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(hintTitle)
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text(hintMessage)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if !store.isConnected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if !store.isConnected { onOpenDevices() }
        }
    }

    private var hintTone: Color {
        if store.isDemo { return Aurora.brand }
        if store.isConnected { return Aurora.teal }
        return Aurora.warning
    }

    private var hintIcon: String {
        if store.isDemo { return "sparkles" }
        if store.isConnected { return store.mode == .relay ? "antenna.radiowaves.left.and.right" : "wifi" }
        return "link.badge.plus"
    }

    private var hintTitle: String {
        if store.isDemo { return "当前是演示画面" }
        if store.isConnected { return store.mode == .relay ? "远程中继已连接" : "局域网直连" }
        return "还没有连上车机"
    }

    private var hintMessage: String {
        if store.isDemo { return "连接车机后即可查看实时监控画面。" }
        if store.isConnected {
            return store.mode == .relay
                ? "画面由车机主动连出中继，适合跨网络查看。"
                : "画面通过 \(store.lanAddress) 直连车机，不经过云端。"
        }
        return "去「设备」页填写车机 IP，或连接远程中继。"
    }

    // MARK: - 连接状态

    private var connectionText: String {
        switch store.connection {
        case .demo: return "演示数据"
        case .connecting: return "连接中"
        case .connected: return store.mode == .relay ? "中继在线" : "局域网在线"
        case .failed: return "未连接"
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

    private var durationText: String {
        guard let status = store.status else { return "—" }
        if status.isRecording { return formatDuration(status.recordingDuration) }
        return "未在录制"
    }
}

// MARK: - 机位放大预览

struct ChannelPreviewView: View {

    let channel: SentinelChannel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SentinelStore

    var body: some View {
        ZStack {
            Color(hex: 0x08060F)
                .ignoresSafeArea()

            if let image = store.frames[channel.id] {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else if store.isDemo {
                DemoFrameView(channelID: channel.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: channel.isOnline ? "hourglass" : "wifi.slash")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text(channel.isOnline ? "正在加载画面…" : "机位离线")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.60), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.66), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(channel.sourceLabel ?? channel.source ?? "摄像头")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.66))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.38)))
                            .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .padding(.top, 8)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formatClock(store.frameDates[channel.id] ?? context.date))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(channel.displayResolution)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                        Text(channel.isOnline ? "\(channel.displayFPS) fps" : "OFFLINE")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(channel.isOnline ? Aurora.teal : Aurora.warning)
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            OrientationLock.shared.isLandscapeAllowed = true
        }
        .onDisappear {
            OrientationLock.shared.isLandscapeAllowed = false
        }
    }
}