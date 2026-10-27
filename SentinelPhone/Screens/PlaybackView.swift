import SwiftUI
import UIKit

enum PlaybackRange: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "浠婂ぉ"
        case .yesterday: return "鏄ㄥぉ"
        case .all: return "鍏ㄩ儴"
        }
    }
}

struct PlaybackView: View {

    @EnvironmentObject private var store: SentinelStore
    @State private var range: PlaybackRange = .all
    @State private var selected: RecordingSession?
    @State private var pendingDelete: RecordingSession?
    @State private var exportURL: URL?
    @State private var exportingID: String?

    private var filtered: [RecordingSession] {
        let sorted = store.sessions.sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
        switch range {
        case .all:
            return sorted
        case .today:
            return sorted.filter { Calendar.current.isDateInToday($0.startDate) }
        case .yesterday:
            return sorted.filter { Calendar.current.isDateInYesterday($0.startDate) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "鍥炴斁", subtitle: "鎸夎疆娆′繚瀛樼殑 JPEG 搴忓垪") {
                TopBarIconButtons(systemIcon: "arrow.clockwise") {
                    store.refreshNow()
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    storageCard
                    filterBar
                    sessionsHeader
                    sessionList
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 2)
                .padding(.bottom, 126)
            }
        }
        .sheet(item: $selected) { session in
            PlaybackSheet(session: session, initialIndex: initialIndex(for: session))
                .environmentObject(store)
        }
        .confirmationDialog(
            "鍒犻櫎杩欐褰曞儚锛?,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("鍒犻櫎", role: .destructive) {
                if let session = pendingDelete {
                    store.deleteSession(id: session.id)
                }
                pendingDelete = nil
            }
            Button("鍙栨秷", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("鍒犻櫎鍚庢棤娉曟仮澶嶏紱姝ｅ湪褰曞埗鐨勬満浣嶄笉鑳藉垹闄ゃ€?)
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .onAppear(perform: openRequestedSession)
        .onChange(of: store.requestedSessionID) { _ in
            openRequestedSession()
        }
    }

    private func initialIndex(for session: RecordingSession) -> Int {
        session.isActive ? 0 : 0
    }

    private func openRequestedSession() {
        guard let id = store.requestedSessionID,
              let session = store.sessions.first(where: { $0.id == id }) else { return }
        store.requestedSessionID = nil
        range = .all
        selected = session
    }

    private func exportSession(_ session: RecordingSession) {
        guard exportingID == nil else { return }
        exportingID = session.id
        Task { @MainActor in
            let url = await store.exportSession(session)
            exportingID = nil
            exportURL = url
        }
    }

    // MARK: - 瀛樺偍

    private var storageCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Aurora.brand.tint(0.13))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("寰幆瀛樺偍")
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                        Text("淇濈暀 \(store.status?.retentionText ?? "3 澶?) 路 \(store.status?.metrics?.recordFps ?? 30) fps")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                    Spacer()
                    Text("\(store.status?.freeText ?? "鈥?) 鍙敤")
                        .font(AuroraFont.labelLarge)
                        .foregroundStyle(Aurora.brandDeep)
                }

                StorageProgress(
                    used: store.status?.storage?.recordBytes ?? 0,
                    total: store.status?.storage?.totalBytes ?? 0
                )

                HStack {
                    Text("宸茬敤 \(store.status?.recordText ?? "鈥?)")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer()
                    Text("鍏?\(formatBytes(store.status?.storage?.totalBytes ?? 0))")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                HStack(spacing: 6) {
                    TinyTag(text: store.status?.retentionText ?? "3 澶?, systemIcon: "calendar", tone: Aurora.brand)
                    TinyTag(text: "640 px", systemIcon: "rectangle.compress.vertical", tone: Aurora.teal)
                    TinyTag(text: "\(store.status?.metrics?.recordFps ?? 30) fps", systemIcon: "speedometer", tone: Aurora.rose)
                }
            }
        }
    }

    // MARK: - 绛涢€?
    private var filterBar: some View {
        HStack(spacing: 7) {
            ForEach(PlaybackRange.allCases) { item in
                FilterChip(text: item.title, selected: range == item) {
                    withAnimation(.easeInOut(duration: 0.18)) { range = item }
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var sessionsHeader: some View {
        HStack {
            Text("褰曞儚鍒楄〃")
                .font(AuroraFont.titleMedium)
                .foregroundStyle(Aurora.ink)
            Text("\(filtered.count)")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
            Spacer()
            if store.isDemo {
                Text("婕旂ず鏁版嵁")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.warning)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var sessionList: some View {
        if filtered.isEmpty {
            SectionCard {
                EmptyStateView(
                    systemIcon: "play.rectangle",
                    title: "杩樻病鏈夊綍鍍?,
                    message: "杞︽満寮€濮嬪綍鍒跺悗锛屾寜杞淇濆瓨鐨勭敾闈細鍑虹幇鍦ㄨ繖閲屻€?
                )
                .padding(.vertical, 12)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(filtered) { session in
                    PlaybackSessionRow(session: session, exporting: exportingID == session.id) {
                        selected = session
                    } onDelete: {
                        pendingDelete = session
                    } onExport: {
                        exportSession(session)
                    }
                }
            }
        }
    }
}

// MARK: - 鍒楄〃琛?
struct PlaybackSessionRow: View {

    let session: RecordingSession
    var exporting: Bool = false
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    @EnvironmentObject private var store: SentinelStore
    @State private var thumbnail: UIImage?

    var body: some View {
        SectionCard {
            HStack(spacing: 11) {
                thumbnailView
                    .frame(width: 94, height: 61)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(session.displayName)
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        if session.isActive {
                            Text("褰曞埗涓?)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Aurora.rose)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Aurora.rose.tint(0.12)))
                        }
                    }
                    Text(dayTimeLabel(session.startDate))
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        TinyTag(text: session.durationText, systemIcon: "clock", tone: Aurora.brand)
                        Text(session.sizeText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Aurora.inkSoft)
                        Text("\(session.count) 甯?)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Aurora.muted)
                    }
                }

                Spacer(minLength: 0)

                if !session.isActive {
                    Button(action: onExport) {
                        ZStack {
                            Circle()
                                .fill(Aurora.brand.tint(0.12))
                            if exporting {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Aurora.brand)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Aurora.brand.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(exporting)
                    Spacer(minLength: 8)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Aurora.rose)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Aurora.rose.tint(0.12)))
                            .overlay(Circle().stroke(Aurora.rose.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    Spacer(minLength: 8)
                }

                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Aurora.brand)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Aurora.brand.tint(0.12)))
                        .overlay(Circle().stroke(Aurora.brand.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onPlay)
        .task(id: session.id) {
            guard thumbnail == nil else { return }
            thumbnail = await store.thumbnail(for: session)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 94, height: 61)
                    .clipped()
            } else if store.isDemo {
                DemoFrameView(channelID: session.channelId ?? "front", animated: false)
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x2C2144), Color(hex: 0x151020)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "video")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                HStack {
                    Text(session.channelName ?? "鏈轰綅")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(formatShortDuration(session.duration))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.88))
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
            }
        }
    }
}

// MARK: - 鎾斁寮圭獥

struct PlaybackSheet: View {

    let session: RecordingSession
    var initialIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SentinelStore
    @State private var index: Int = 0
    @State private var isPlaying = true
    @State private var wasPlaying = true
    @State private var image: UIImage?

    private var frameCount: Int { max(1, session.count) }
    private var interval: TimeInterval { max(0.033, session.interval) }
    private var currentDate: Date {
        session.startDate.addingTimeInterval(Double(index) * interval)
    }
    private var channelID: String { session.channelId ?? "front" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 11) {
                    player
                    controls
                    metadata
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
        .background(Aurora.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task(id: session.id) {
            index = min(max(0, initialIndex), frameCount - 1)
            await loadFrame()
        }
        .task(id: isPlaying) {
            if isPlaying { await playbackLoop() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("鍥炴斁")
                    .font(AuroraFont.headlineSmall)
                    .foregroundStyle(Aurora.ink)
                Text("\(session.displayName) 路 \(dayTimeLabel(session.startDate))")
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
            }
            Spacer()
            AuroraIconButton(systemIcon: "xmark", tone: Aurora.inkSoft, size: 36) {
                dismiss()
            }
            AuroraIconButton(systemIcon: "square.and.arrow.up", tone: Aurora.brand, size: 36) {
                share()
            }
        }
        .padding(.horizontal, AuroraMetrics.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - 鎾斁鍣?
    private var player: some View {
        ZStack {
            Color(hex: 0x0C0912)

            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else if store.isDemo {
                DemoFrameView(channelID: channelID)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text(session.isActive ? "杩欎竴杞繕鍦ㄥ綍鍒? : "姝ｅ湪璇诲彇鐢婚潰鈥?)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.62), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.channelName ?? "鏈轰綅")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(dayTimeLabel(session.startDate))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    Spacer()
                    Text("\(index + 1) / \(frameCount)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.34)))
                }
                Spacer()
                HStack {
                    Text(formatClock(currentDate))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(session.resolutionText)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .padding(12)

            if !isPlaying {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Aurora.brandDeep)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(Color.white.opacity(0.88)))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - 鎺у埗

    private var controls: some View {
        SectionCard {
            VStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(index) },
                        set: { value in
                            index = min(max(0, Int(value)), frameCount - 1)
                        }
                    ),
                    in: 0...Double(max(1, frameCount - 1)),
                    onEditingChanged: { editing in
                        if editing {
                            wasPlaying = isPlaying
                            isPlaying = false
                        } else {
                            Task { await loadFrame() }
                            if wasPlaying { isPlaying = true }
                        }
                    }
                )
                .tint(Aurora.brand)

                HStack(spacing: 18) {
                    Text(formatShortDuration(Double(index) * interval))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.inkSoft)
                        .frame(width: 44, alignment: .leading)

                    Spacer()

                    Button {
                        seek(by: -10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Aurora.inkSoft)
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle().fill(Aurora.brandGradient)
                            )
                            .shadow(color: Aurora.brand.opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        seek(by: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Aurora.inkSoft)
                    }
                    .buttonStyle(PressScaleStyle())

                    Spacer()

                    Text(formatShortDuration(session.duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Aurora.muted)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var metadata: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AuroraSectionHeader(
                    title: "褰曞儚淇℃伅",
                    subtitle: "JPEG 搴忓垪鍥炴斁",
                    systemIcon: "info.circle",
                    trailingText: "\(frameCount) 甯?
                )
                Divider().background(Aurora.line.opacity(0.6))
                InfoRow(label: "寮€濮嬫椂闂?, value: formatTime(session.startDate), systemIcon: "calendar")
                InfoRow(label: "鏃堕暱", value: session.durationText, systemIcon: "clock")
                InfoRow(label: "鍒嗚鲸鐜?, value: session.resolutionText, systemIcon: "rectangle")
                InfoRow(label: "甯х巼", value: String(format: "%.1f fps", 1 / interval), systemIcon: "speedometer")
                InfoRow(label: "澶у皬", value: session.sizeText, systemIcon: "externaldrive")
            }
        }
    }

    // MARK: - 鎾斁閫昏緫

    @MainActor
    private func togglePlay() {
        if !isPlaying, index >= frameCount - 1 {
            index = 0
            Task { await loadFrame() }
        }
        isPlaying.toggle()
    }

    @MainActor
    private func seek(by delta: Int) {
        index = min(max(0, index + delta), frameCount - 1)
        Task { await loadFrame() }
    }

    @MainActor
    private func loadFrame() async {
        guard !store.isDemo else {
            image = nil
            return
        }
        image = await store.playbackFrame(session: session, index: index)
    }

    @MainActor
    private func playbackLoop() async {
        while !Task.isCancelled && isPlaying {
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, isPlaying else { return }
            index = (index + 1) % frameCount
            await loadFrame()
        }
    }

    @MainActor
    private func share() {
        // 鍥炴斁鐩墠鏄彧璇绘煡鐪嬶紱鍒嗕韩鍏ュ彛淇濈暀缁欏悗缁鍑哄崟甯с€?    }
}


struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}