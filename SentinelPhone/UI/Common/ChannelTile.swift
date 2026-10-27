import SwiftUI
import UIKit

/// 四宫格里的单个机位卡片。
struct ChannelTile: View {

    let channel: SentinelChannel
    var image: UIImage? = nil
    var timestamp: Date? = nil
    var isDemo: Bool = false
    var error: String? = nil

    private var online: Bool { channel.isOnline }

    var body: some View {
        ZStack {
            Color(hex: 0x0D0A14)

            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .transition(.opacity)
            } else if isDemo {
                DemoFrameView(channelID: channel.id)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: error == nil ? "hourglass" : "wifi.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                    Text(error == nil ? (online ? "等待画面" : "机位离线") : "画面中断")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            // 上下暗角，保证文字可读
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.52), location: 0),
                    .init(color: .clear, location: 0.32),
                    .init(color: .clear, location: 0.60),
                    .init(color: .black.opacity(0.58), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Text(channel.displayShort)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                        Text(channel.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.34)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(online ? Aurora.rose : Aurora.warning)
                            .frame(width: 5, height: 5)
                        Text(online ? "LIVE" : "OFFLINE")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.36)))
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formatClock(timestamp ?? context.date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    Spacer(minLength: 0)
                    Text(channel.displayResolution)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .padding(9)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
    }
}
