import SwiftUI
import UIKit

enum EventFilter: String, CaseIterable, Identifiable {
    case all
    case motion
    case shock
    case offline
    case manual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .motion: return "移动"
        case .shock: return "震动"
        case .offline: return "离线"
        case .manual: return "抓拍"
        }
    }
    var icon: String? {
        switch self {
        case .all: return nil
        case .motion: return "figure.walk"
        case .shock: return "waveform.path.ecg"
        case .offline: return "wifi.slash"
        case .manual: return "camera"
        }
    }
    func matches(_ event: SentinelEvent) -> Bool {
        switch self {
        case .all: return true
        case .motion: return event.kind == "MOTION"
        case .shock: return event.kind == "SHOCK"
        case .offline: return event.kind == "CAMERA_OFFLINE"
        case .manual: return event.kind == "MANUAL"
        }
    }
}

struct EventsView: View {

    @EnvironmentObject private var store: SentinelStore
    var onOpenPlayback: (String) -> Void = { _ in }

    @State private var filter: EventFilter = .all
    @State private var selected: SentinelEvent?

    private var filtered: [SentinelEvent] {
        store.events
            .filter { filter.matches($0) }
            .sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
    }

    private var todayCount: Int {
        store.events.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var importantCount: Int {
        store.events.filter { ($0.severity ?? 1) >= 2 }.count
    }

    private var urgentCount: Int {
        store.events.filter { ($0.severity ?? 1) >= 3 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(title: "事件", subtitle: "移动 / 震动 / 离线 / 抓拍") {
                AuroraIconButton(systemIcon: "arrow.clockwise", size: 38) {
                    store.refreshNow()
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    summaryCard
                    filterBar
                    eventList
                }
                .padding(.horizontal, AuroraMetrics.pagePadding)
                .padding(.top, 2)
                .padding(.bottom, 126)
            }
        }
        .sheet(item: $selected) { event in
            EventDetailSheet(event: event) { sessionID in
                onOpenPlayback(sessionID)
            }
            .environmentObject(store)
        }
    }

    private var summaryCard: some View {
        SectionCard {
            HStack(spacing: 0) {
                summaryCell(value: "\(todayCount)", label: "今日事件", tone: Aurora.brand)
                summaryDivider
                summaryCell(value: "\(importantCount)", label: "重要", tone: Aurora.warning)
                summaryDivider
                summaryCell(value: "\(urgentCount)", label: "紧急", tone: Aurora.rose)
            }
        }
    }

    private func summaryCell(value: String, label: String, tone: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tone)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Aurora.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Aurora.line.opacity(0.55))
            .frame(width: 1, height: 30)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(EventFilter.allCases) { item in
                    FilterChip(text: item.title, systemIcon: item.icon, selected: filter == item) {
                        withAnimation(.easeInOut(duration: 0.16)) { filter = item }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .padding(.horizontal, -2)
    }

    @ViewBuilder
    private var eventList: some View {
        if filtered.isEmpty {
            SectionCard {
                EmptyStateView(
                    systemIcon: "bell.slash",
                    title: "没有这类事件",
                    message: "车机检测到移动、震动或离线时，会自动记录在这里。"
                )
                .padding(.vertical, 12)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(filtered) { event in
                    EventRow(event: event) {
                        selected = event
                    }
                }
            }
        }
    }
}

// MARK: - 事件行

struct EventRow: View {

    let event: SentinelEvent
    let onTap: () -> Void

    var body: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(event.kindTone.tint(0.14))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: event.kindIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(event.kindTone)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(event.displayTitle)
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(formatRelative(event.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Aurora.muted)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(event.kindLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(event.kindTone)
                        Text("·")
                            .foregroundStyle(Aurora.muted)
                        Text(event.displayChannel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Aurora.inkSoft)
                        if (event.severity ?? 1) >= 2 {
                            Text(event.severityLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(event.severityTone)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(event.severityTone.tint(0.12)))
                        }
                    }

                    Text(event.displayDetail)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if event.clipSessionId != nil || event.hasSnapshot == true {
                        HStack(spacing: 5) {
                            if event.hasSnapshot == true {
                                TinyTag(text: "快照", systemIcon: "photo", tone: Aurora.teal)
                            }
                            if event.clipSessionId != nil {
                                TinyTag(text: "有录像", systemIcon: "film", tone: Aurora.brand)
                            }
                        }
                    }
                }

                EventThumbnail(event: event)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

struct EventThumbnail: View {

    let event: SentinelEvent
    @EnvironmentObject private var store: SentinelStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipped()
            } else if store.isDemo {
                DemoFrameView(channelID: event.channelId ?? "front", animated: false)
            } else {
                LinearGradient(
                    colors: [event.kindTone.opacity(0.50), Color(hex: 0x151020)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: event.kindIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                HStack {
                    Image(systemName: event.kindIcon)
                        .font(.system(size: 8, weight: .bold))
                    Spacer()
                    if event.clipSessionId != nil {
                        Image(systemName: "film")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.bottom, 4)
            }
        }
        .task(id: event.id) {
            guard image == nil, !store.isDemo else { return }
            image = await store.snapshot(for: event)
        }
    }
}

// MARK: - 详情

struct EventDetailSheet: View {

    let event: SentinelEvent
    var onOpenPlayback: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SentinelStore

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    snapshot
                    detailCard
                    if let sessionID = event.clipSessionId {
                        playbackAction(sessionID: sessionID)
                    }
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("事件详情")
                    .font(AuroraFont.headlineSmall)
                    .foregroundStyle(Aurora.ink)
                Text(formatTime(event.date))
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
            }
            Spacer()
            AuroraIconButton(systemIcon: "xmark", tone: Aurora.inkSoft, size: 36) {
                dismiss()
            }
        }
        .padding(.horizontal, AuroraMetrics.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var snapshot: some View {
        ZStack {
            Color(hex: 0x0C0912)
            EventBigImage(event: event)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .black.opacity(0.55), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: event.kindIcon)
                            .font(.system(size: 10, weight: .bold))
                        Text(event.kindLabel)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.36)))
                    Spacer()
                    if let channel = event.channelName {
                        Text(channel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.36)))
                    }
                }
                Spacer()
                HStack {
                    Text(formatClock(event.date))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    if event.hasSnapshot == true {
                        Text("EVENT SNAPSHOT")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var detailCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(event.displayTitle)
                        .font(AuroraFont.titleLarge)
                        .foregroundStyle(Aurora.ink)
                    Spacer()
                    StatusPill(text: event.severityLabel, color: event.severityTone)
                }
                HStack(spacing: 6) {
                    TinyTag(text: event.kindLabel, systemIcon: event.kindIcon, tone: event.kindTone)
                    TinyTag(text: event.displayChannel, systemIcon: "video", tone: Aurora.teal)
                    if let clip = event.clip, let count = clip.count, count > 0 {
                        TinyTag(text: "\(count) 帧", systemIcon: "film", tone: Aurora.brand)
                    }
                }
                Divider().background(Aurora.line.opacity(0.6))
                Text(event.displayDetail)
                    .font(AuroraFont.bodyMedium)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func playbackAction(sessionID: String) -> some View {
        VStack(spacing: 8) {
            BrandButton(text: "在回放中查看", systemIcon: "play.rectangle.fill") {
                dismiss()
                onOpenPlayback(sessionID)
            }
            Text("会打开这次事件前后的连续录像，按 2 fps 回放。")
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 2)
    }
}

struct EventBigImage: View {

    let event: SentinelEvent
    @EnvironmentObject private var store: SentinelStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else if store.isDemo {
                DemoFrameView(channelID: event.channelId ?? "front")
            } else {
                ZStack {
                    LinearGradient(
                        colors: [event.kindTone.opacity(0.45), Color(hex: 0x151020)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: event.kindIcon)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
        }
        .task(id: event.id) {
            guard image == nil, !store.isDemo else { return }
            image = await store.snapshot(for: event)
        }
    }
}
