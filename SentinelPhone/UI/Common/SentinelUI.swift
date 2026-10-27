import SwiftUI

// MARK: - 品牌实心按钮（连接、主要动作）

struct BrandButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(text)
                    .font(AuroraFont.labelLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Aurora.brandGradient)
                    .shadow(color: Aurora.brand.opacity(0.22), radius: 5, x: 0, y: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - 录制按钮

struct RecordControlButton: View {

    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 13, weight: .bold))
                Text(isRecording ? "停止录制" : "开始录制")
                    .font(AuroraFont.labelLarge)
            }
            .foregroundStyle(isRecording ? Aurora.rose : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Aurora.rose.tint(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(Aurora.rose.opacity(0.24), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Aurora.brandGradient)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - 指标

struct MetricCell: View {

    let systemIcon: String
    let label: String
    let value: String
    var tone: Color = Aurora.brand

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tone.tint(0.13))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: systemIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tone)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 筛选胶囊

struct FilterChip: View {

    let text: String
    var systemIcon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(text)
                    .font(AuroraFont.labelMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Aurora.brandDeep : Aurora.inkSoft)
            .padding(.horizontal, 13)
            .frame(height: 33)
            .background(
                Capsule()
                    .fill(selected ? Aurora.brand.tint(0.14) : Aurora.surface)
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Aurora.brand.opacity(0.18) : Aurora.line.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - 小标签

struct TinyTag: View {

    let text: String
    var systemIcon: String? = nil
    var tone: Color = Aurora.muted

    var body: some View {
        HStack(spacing: 4) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tone.tint(0.10)))
    }
}

// MARK: - 信息行

struct InfoRow: View {

    let label: String
    let value: String
    var valueColor: Color = Aurora.ink
    var systemIcon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Aurora.muted)
                    .frame(width: 16)
            }
            Text(label)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(AuroraFont.labelMedium)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - 存储条

struct StorageProgress: View {

    let used: Double
    let total: Double

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, used / total))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Aurora.surfaceVariant)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Aurora.brand, Aurora.brandDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - 事件颜色

extension SentinelEvent {

    var kindTone: Color {
        switch kind {
        case "MOTION": return Aurora.brand
        case "SHOCK": return Aurora.rose
        case "CAMERA_OFFLINE": return Aurora.warning
        case "MANUAL": return Aurora.teal
        default: return Aurora.muted
        }
    }

    var severityTone: Color {
        switch severity ?? 1 {
        case 3: return Aurora.rose
        case 2: return Aurora.warning
        default: return Aurora.muted
        }
    }
}

// MARK: - 日期

func dayTimeLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: date)
    if Calendar.current.isDateInToday(date) { return "今天 \(time)" }
    if Calendar.current.isDateInYesterday(date) { return "昨天 \(time)" }
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}

func dayOnlyLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return "今天" }
    if Calendar.current.isDateInYesterday(date) { return "昨天" }
    return formatDay(date)
}
