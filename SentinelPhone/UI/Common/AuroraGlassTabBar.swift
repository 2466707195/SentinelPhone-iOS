import SwiftUI

enum SentinelTab: String, CaseIterable, Identifiable {
    case realtime
    case playback
    case events
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realtime: return "实时画面"
        case .playback: return "回放"
        case .events: return "事件"
        case .device: return "设备"
        }
    }

    var icon: String {
        switch self {
        case .realtime: return "video"
        case .playback: return "play.rectangle"
        case .events: return "bell"
        case .device: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .realtime: return "video.fill"
        case .playback: return "play.rectangle.fill"
        case .events: return "bell.fill"
        case .device: return "gearshape.fill"
        }
    }
}

/// 透明玻璃底栏。iOS 26 用真正的 Liquid Glass：底栏 `.clear`，选中胶囊 `.regular`，
/// 两者放进同一个 `GlassEffectContainer`，靠近时才会融合出透镜感。
struct AuroraGlassTabBar: View {

    @Binding var selection: SentinelTab

    private let inset: CGFloat = 6
    private let capsuleInset: CGFloat = 4
    private let barHeight: CGFloat = 68

    @State private var dragCapsuleX: CGFloat?
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let itemWidth = max(1, (width - inset * 2) / CGFloat(SentinelTab.allCases.count))
            let capsuleWidth = max(1, itemWidth - capsuleInset * 2)
            let targetX = xFor(
                index: SentinelTab.allCases.firstIndex(of: selection) ?? 0,
                inset: inset,
                itemWidth: itemWidth,
                capsuleWidth: capsuleWidth
            )

            ZStack(alignment: .leading) {
                barLayer(
                    width: width,
                    itemWidth: itemWidth,
                    capsuleWidth: capsuleWidth,
                    targetX: targetX
                )

                HStack(spacing: 0) {
                    ForEach(SentinelTab.allCases) { tab in
                        item(tab: tab, itemWidth: itemWidth)
                    }
                }
            }
            .frame(width: width, height: barHeight)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onTapGesture { }
            .simultaneousGesture(dragGesture(width: width, itemWidth: itemWidth, capsuleWidth: capsuleWidth))
        }
        .frame(height: barHeight)
        .shadow(color: Aurora.barShadow, radius: 14, x: 0, y: 6)
    }

    @ViewBuilder
    private func barLayer(
        width: CGFloat,
        itemWidth: CGFloat,
        capsuleWidth: CGFloat,
        targetX: CGFloat
    ) -> some View {
        let capsuleX = dragCapsuleX ?? targetX
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: width, height: barHeight)
                        .glassEffect(.clear.interactive(), in: AuroraShape.bar)

                    Capsule()
                        .fill(Color.clear)
                        .frame(width: capsuleWidth, height: 54)
                        .offset(x: capsuleX)
                        .glassEffect(
                            .regular
                                .tint(Aurora.brand.opacity(0.16))
                                .interactive(),
                            in: Capsule()
                        )
                        .shadow(color: Aurora.brand.opacity(0.10), radius: 4, x: 0, y: 2)
                }
            }
        } else {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AuroraShape.bar)
                    .frame(width: width, height: barHeight)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Aurora.brand.opacity(0.20),
                                Aurora.brand.opacity(0.12),
                                Aurora.teal.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.65), Aurora.brand.opacity(0.20)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .frame(width: capsuleWidth, height: 54)
                    .offset(x: capsuleX)
                    .shadow(color: Aurora.brand.opacity(0.12), radius: 4, x: 0, y: 2)
            }
            .auroraGlassSurface(
                AuroraShape.bar,
                tone: .white,
                tint: 0.06,
                border: 0.22,
                shadowRadius: 0,
                shadowY: 0
            )
        }
    }

    private func item(tab: SentinelTab, itemWidth: CGFloat) -> some View {
        let selected = selection == tab
        return VStack(spacing: 3) {
            Image(systemName: selected ? tab.selectedIcon : tab.icon)
                .font(.system(size: 17, weight: selected ? .semibold : .regular))
                .frame(height: 20)
            Text(tab.title)
                .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? Aurora.brandDeep : Aurora.inkSoft)
        .frame(width: itemWidth, height: barHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !dragging else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                selection = tab
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func dragGesture(width: CGFloat, itemWidth: CGFloat, capsuleWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragging = true
                let index = SentinelTab.allCases.firstIndex(of: selection) ?? 0
                let start = xFor(index: index, inset: inset, itemWidth: itemWidth, capsuleWidth: capsuleWidth)
                let minX = inset + capsuleInset
                let maxX = width - inset - capsuleInset - capsuleWidth
                dragCapsuleX = min(max(start + value.translation.width, minX), maxX)
            }
            .onEnded { _ in
                let currentX = dragCapsuleX ?? xFor(
                    index: SentinelTab.allCases.firstIndex(of: selection) ?? 0,
                    inset: inset,
                    itemWidth: itemWidth,
                    capsuleWidth: capsuleWidth
                )
                let center = currentX + capsuleWidth / 2
                let raw = (center - inset) / itemWidth
                let index = min(SentinelTab.allCases.count - 1, max(0, Int(raw.rounded())))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                    selection = SentinelTab.allCases[index]
                    dragCapsuleX = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    dragging = false
                }
            }
    }

    private func xFor(index: Int, inset: CGFloat, itemWidth: CGFloat, capsuleWidth: CGFloat) -> CGFloat {
        inset + capsuleInset + CGFloat(index) * itemWidth
    }
}
