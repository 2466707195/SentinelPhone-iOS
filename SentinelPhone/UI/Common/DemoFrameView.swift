import SwiftUI

/// 演示画面：不依赖网络，用透视车道 + 缓慢流动的虚线模拟行车记录仪。
/// 四个机位使用不同色调，避免四宫格看起来完全一样。
struct DemoFrameView: View {

    let channelID: String
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !animated)) { timeline in
            Canvas { context, size in
                draw(
                    context: &context,
                    size: size,
                    time: animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                )
            }
        }
        .background(Color(hex: 0x100D18))
    }

    private var palette: (top: Color, bottom: Color, glow: Color, line: Color) {
        switch channelID {
        case "rear":
            return (Color(hex: 0x123039), Color(hex: 0x081318), Color(hex: 0x38C7C9), Color(hex: 0x8BE7E3))
        case "left":
            return (Color(hex: 0x331A2D), Color(hex: 0x150B17), Color(hex: 0xD45C9B), Color(hex: 0xF4A7C8))
        case "right":
            return (Color(hex: 0x24243A), Color(hex: 0x0E101C), Color(hex: 0x7B8BE8), Color(hex: 0xC3C9FF))
        default:
            return (Color(hex: 0x2B2044), Color(hex: 0x100C1D), Color(hex: 0x8A63E8), Color(hex: 0xD3C4FF))
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 1, size.height > 1 else { return }
        let colors = palette
        let full = Path(CGRect(origin: .zero, size: size))

        context.fill(
            full,
            with: .linearGradient(
                Gradient(colors: [colors.top, colors.bottom]),
                startPoint: CGPoint(x: size.width * 0.5, y: 0),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )

        let horizonY = size.height * 0.42

        // 地平线光晕
        let glowRect = CGRect(
            x: -size.width * 0.25,
            y: horizonY - size.height * 0.34,
            width: size.width * 1.5,
            height: size.height * 0.68
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [colors.glow.opacity(0.42), colors.glow.opacity(0.10), .clear]),
                center: CGPoint(x: size.width * 0.5, y: horizonY),
                startRadius: 0,
                endRadius: size.width * 0.72
            )
        )

        // 远处城市剪影（固定节奏，避免每帧抖动）
        var skyline = Path()
        skyline.move(to: CGPoint(x: 0, y: horizonY))
        var x: CGFloat = 0
        let skylineHeight = size.height * 0.16
        let heightSteps: [CGFloat] = [0.42, 0.68, 0.55, 0.90, 0.35, 0.74, 0.50, 0.82]
        var block = 0
        while x < size.width {
            let width = CGFloat(7 + (block % 3) * 4)
            let height = heightSteps[block % heightSteps.count] * skylineHeight
            skyline.addLine(to: CGPoint(x: x, y: horizonY - height))
            skyline.addLine(to: CGPoint(x: x + width, y: horizonY - height))
            x += width + 2
            block += 1
        }
        skyline.addLine(to: CGPoint(x: size.width, y: horizonY))
        skyline.closeSubpath()
        context.fill(skyline, with: .color(Color.black.opacity(0.28)))

        // 路面
        var road = Path()
        road.move(to: CGPoint(x: -size.width * 0.18, y: size.height))
        road.addLine(to: CGPoint(x: size.width * 0.43, y: horizonY))
        road.addLine(to: CGPoint(x: size.width * 0.57, y: horizonY))
        road.addLine(to: CGPoint(x: size.width * 1.18, y: size.height))
        road.closeSubpath()
        context.fill(
            road,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.10), Color.black.opacity(0.28)]),
                startPoint: CGPoint(x: size.width * 0.5, y: horizonY),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )

        // 路缘
        var leftEdge = Path()
        leftEdge.move(to: CGPoint(x: -size.width * 0.18, y: size.height))
        leftEdge.addLine(to: CGPoint(x: size.width * 0.43, y: horizonY))
        var rightEdge = Path()
        rightEdge.move(to: CGPoint(x: size.width * 1.18, y: size.height))
        rightEdge.addLine(to: CGPoint(x: size.width * 0.57, y: horizonY))
        context.stroke(leftEdge, with: .color(colors.line.opacity(0.25)), lineWidth: 1)
        context.stroke(rightEdge, with: .color(colors.line.opacity(0.25)), lineWidth: 1)

        // 车道虚线：越靠近地平线越细，随 time 向远处流动
        let phase = time.truncatingRemainder(dividingBy: 1.5) / 1.5
        for index in 0..<8 {
            let t = (Double(index) + phase) / 8.0
            let y = size.height - (size.height - horizonY) * CGFloat(t)
            let dashWidth = max(1.2, 6 * (1 - CGFloat(t)))
            let dashHeight = max(2, 30 * (1 - CGFloat(t)))
            let rect = CGRect(x: size.width * 0.5 - dashWidth / 2, y: y, width: dashWidth, height: dashHeight)
            context.fill(
                Path(roundedRect: rect, cornerRadius: dashWidth / 2),
                with: .color(Color.white.opacity(0.34 * (1 - CGFloat(t) * 0.65)))
            )
        }

        // 两侧车灯散射
        for side in [CGFloat(0.16), CGFloat(0.84)] {
            let lightRect = CGRect(
                x: size.width * side - size.width * 0.22,
                y: size.height * 0.62,
                width: size.width * 0.44,
                height: size.height * 0.50
            )
            context.fill(
                Path(ellipseIn: lightRect),
                with: .radialGradient(
                    Gradient(colors: [colors.line.opacity(0.18), .clear]),
                    center: CGPoint(x: size.width * side, y: size.height * 0.80),
                    startRadius: 0,
                    endRadius: size.width * 0.26
                )
            )
        }

        // 轻微暗角
        context.fill(
            full,
            with: .radialGradient(
                Gradient(colors: [.clear, Color.black.opacity(0.40)]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: size.width * 0.25,
                endRadius: size.width * 0.78
            )
        )
    }
}
