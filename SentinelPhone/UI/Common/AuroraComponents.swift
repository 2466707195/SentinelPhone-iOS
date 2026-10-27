import Foundation
import SwiftUI

// === Aurora UI 閫氱敤缁勪欢锛坕OS / SwiftUI锛?==
// 瀵瑰簲 Android 鐗?`ui/common/Common.kt`銆?
// MARK: - 鏋佸厜鑳屾櫙

/// 鏋佸厜鑳屾櫙锛氳繎鐧藉簳 + 涓夊洟寰堟贰鐨勫緞鍚戣壊鏅曪紝缁欏疄鐧藉崱鐗囨彁渚涘眰娆★紝浣嗕笉鎶㈠唴瀹广€?///
/// 瑙勫垯锛?*鑳屾櫙鍙互娣★紝鍐呭蹇呴』瀹?*銆傝壊鏅曞彧瀛樺湪浜庡崱鐗囦箣闂寸殑缂濋殭閲屻€?struct AuroraBackdrop: View {

    /// 娣辫壊搴曚笂鑹叉檿闇€瑕佹洿浜墠鐪嬪緱鍑烘潵
    private var boost: Double { Aurora.isDark ? 1.8 : 1.0 }

    var body: some View {
        Canvas { context, size in
            let strength = Aurora.glowStrength * boost

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Aurora.canvas)
            )
            drawGlow(
                in: &context,
                size: size,
                color: Aurora.glowA.opacity(0.11 * strength),
                center: CGPoint(x: size.width * 0.16, y: size.height * 0.02),
                radius: size.width * 0.85
            )
            drawGlow(
                in: &context,
                size: size,
                color: Aurora.glowB.opacity(0.08 * strength),
                center: CGPoint(x: size.width * 1.04, y: size.height * 0.68),
                radius: size.width * 0.80
            )
            drawGlow(
                in: &context,
                size: size,
                color: Aurora.glowC.opacity(0.05 * strength),
                center: CGPoint(x: size.width * 0.02, y: size.height * 0.98),
                radius: size.width * 0.70
            )
        }
        .ignoresSafeArea()
    }

    private func drawGlow(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        center: CGPoint,
        radius: CGFloat
    ) {
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [color, .clear]),
            center: center,
            startRadius: 0,
            endRadius: max(radius, 1)
        )
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: shading
        )
    }
}

// MARK: - 椤舵爮

/// 鑷粯椤舵爮锛屾浛浠ｇ郴缁?NavigationBar銆?struct AppTopBar<Actions: View>: View {

    let title: String
    var subtitle: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Aurora.ink)
                        .frame(width: AuroraMetrics.iconButtonSize, height: AuroraMetrics.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                Spacer().frame(width: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(onBack == nil ? AuroraFont.headlineSmall : AuroraFont.titleLarge)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions()
        }
        .padding(.leading, onBack == nil ? 20 : 4)
        .padding(.trailing, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}


extension AppTopBar where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

// MARK: - 搴曢儴鎿嶄綔鏉?
/// 搴曢儴鎮诞鎿嶄綔鏉★細瀹炵櫧搴?+ 缁嗘弿杈?+ 鏌斿寲鎶曞奖銆?///
/// 铏界劧鍙?"Glass"锛屼絾瀹炵幇鏄?*瀹炵櫧**锛氫笉瑕佹敼鎴愬崐閫忔槑锛?/// 鍗婇€忔槑搴曚細鎶婇槾褰遍€忎笂鏉ワ紝鐪嬭捣鏉ュ儚澶氬灚浜嗕竴灞傜伆鏂瑰潡銆?struct GlassBar<Content: View>: View {

    var contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(contentPadding)
            .background(
                AuroraShape.bar
                    .fill(Aurora.surface)
                    .shadow(color: Aurora.barShadow, radius: 10, x: 0, y: 4)
            )
            .overlay(
                AuroraShape.bar.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
            )
            // 娴眰蹇呴』鏁村潡鍚炵偣鍑伙細绌虹櫧澶勭偣鍑讳笉鑳界┛閫忓埌搴曚笅鐨勫垪琛ㄩ」
            .contentShape(AuroraShape.bar)
            .onTapGesture { }
    }
}

// MARK: - 鍐呭鍗＄墖

/// 鍐呭鍗＄墖鐨勫敮涓€鍏ュ彛銆傚疄鐧姐€?0pt 鍦嗚銆?pt 鎻忚竟銆?pt 闃村奖銆?6pt 鍐呰竟璺濄€?struct SectionCard<Content: View>: View {

    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(AuroraMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AuroraShape.card
                    .fill(Aurora.surface)
                    .shadow(color: Aurora.cardShadow, radius: 4, x: 0, y: 1)
            )
            .overlay(
                AuroraShape.card.stroke(Aurora.line.opacity(0.55), lineWidth: 1)
            )
    }
}

// MARK: - 鍗＄墖鏍囬

/// 鍗＄墖鍐呯粺涓€鏍峰紡鐨勫皬鏍囬锛氬彲閫夊浘鏍囥€佽鏄庡拰鍙充晶璁℃暟銆?///
/// 椤甸潰閲屼笉瑕佸啀鐢ㄨ８鐨?`HStack + Text` 鎷兼爣棰橈紝淇濊瘉瀛楀彿銆侀鑹插拰闂磋窛涓€鑷淬€?struct AuroraSectionHeader: View {

    let title: String
    var subtitle: String? = nil
    var systemIcon: String? = nil
    var tone: Color = Aurora.brand
    var trailingText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemIcon {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.tint(0.13))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: systemIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tone)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let trailingText {
                Text(trailingText)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 鎻愮ず鏉?
/// 缁熶竴鐨勬彁绀烘潯锛氬疄鑹叉贰搴?+ 璇箟鑹叉枃瀛椼€?///
/// 涓嶅啀鍦ㄩ〉闈㈤噷鍐?`background.opacity(...)`锛屼綆鏄庡害搴曚細閫忓嚭鍗＄墖闃村奖銆?struct AuroraBanner: View {

    let systemIcon: String
    let text: String
    var tone: Color = Aurora.warning

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone)
                .padding(.top, 1)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tone.tint(0.13))
        )
    }
}

// MARK: - 椤舵爮鍥炬爣鎸夐挳

/// 椤舵爮鏍囧噯鍥炬爣鎸夐挳锛氬渾褰㈢幓鐠冨簳锛屽彲鍏抽棴鏃惰嚜鍔ㄩ檷閫忔槑搴︺€?struct AuroraIconButton: View {

    let systemIcon: String
    var tone: Color = Aurora.brand
    var size: CGFloat = 40
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: size, height: size)
                .auroraGlassSurface(
                    Circle(),
                    tone: Aurora.inkSoft,
                    tint: 0,
                    border: 0.16,
                    shadowRadius: 0
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - 鐘舵€佽兌鍥?
/// 鐘舵€佽兌鍥婏細灏忓渾鐐?+ 鏂囧瓧锛屽彲鐐瑰嚮鏌ョ湅璇︽儏銆?struct StatusPill: View {

    let text: String
    let color: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(AuroraFont.labelSmall)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.tint(0.13)))
        .contentShape(Capsule())
        .onTapGesture { onTap?() }
    }
}

// MARK: - 棣栧瓧鏂瑰潡

/// 棣栧瓧鍦嗚鏂瑰潡锛屼唬鏇垮浘鏍囷紝閬垮厤"绾枃瀛楀伐绋嬫劅"銆?struct Monogram: View {

    let name: String
    let tone: Color
    var size: CGFloat = 44

    private var letter: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(tone.tint(0.13))
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(AuroraFont.titleMedium)
                    .fontWeight(.bold)
                    .foregroundStyle(tone)
            )
    }
}

// MARK: - 绌虹姸鎬佹彃鐢?
/// 绌虹姸鎬佹彃鐢伙細浜?+ 涓嬬澶淬€?struct DownloadIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let primary = Aurora.brand

            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.5 - w * 0.42, y: h * 0.52 - w * 0.42,
                    width: w * 0.84, height: w * 0.84
                )),
                with: .color(primary.opacity(0.07))
            )

            // 浜?            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.40 - w * 0.16, y: h * 0.35 - w * 0.16,
                    width: w * 0.32, height: w * 0.32
                )),
                with: .color(primary.opacity(0.28))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.58 - w * 0.22, y: h * 0.32 - w * 0.22,
                    width: w * 0.44, height: w * 0.44
                )),
                with: .color(primary.opacity(0.28))
            )
            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.32, y: h * 0.36, width: w * 0.42, height: h * 0.14
                ), cornerRadius: w * 0.06),
                with: .color(primary.opacity(0.28))
            )

            // 鍚戜笅绠ご
            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.475, y: h * 0.48, width: w * 0.05, height: h * 0.28
                ), cornerRadius: w * 0.025),
                with: .color(primary)
            )
            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.40, y: h * 0.70, width: w * 0.20, height: h * 0.05
                ), cornerRadius: w * 0.02),
                with: .color(primary)
            )

            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.78 - w * 0.021, y: h * 0.41 - w * 0.021,
                    width: w * 0.042, height: w * 0.042
                )),
                with: .color(Color.white.opacity(0.9))
            )
        }
        .frame(width: 152, height: 122)
    }
}

/// 绌虹姸鎬佹彃鐢伙細鎼滅储鏀惧ぇ闀溿€?struct SearchIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let primary = Aurora.brand

            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.5 - w * 0.42, y: h * 0.52 - w * 0.42,
                    width: w * 0.84, height: w * 0.84
                )),
                with: .color(primary.opacity(0.07))
            )

            let ring = Path(ellipseIn: CGRect(
                x: w * 0.46 - w * 0.20, y: h * 0.44 - w * 0.20,
                width: w * 0.40, height: w * 0.40
            ))
            context.stroke(ring, with: .color(Color.white), lineWidth: w * 0.05)
            context.stroke(ring, with: .color(primary), lineWidth: w * 0.035)

            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.62, y: h * 0.58, width: w * 0.24, height: h * 0.055
                ), cornerRadius: w * 0.028),
                with: .color(primary)
            )
        }
        .frame(width: 152, height: 122)
    }
}

/// 绌虹姸鎬佹彃鐢伙細鏂囦欢鍒楄〃銆?struct FileListIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let primary = Aurora.brand

            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.5 - w * 0.42, y: h * 0.52 - w * 0.42,
                    width: w * 0.84, height: w * 0.84
                )),
                with: .color(primary.opacity(0.07))
            )

            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.14, y: h * 0.22, width: w * 0.58, height: h * 0.20
                ), cornerRadius: w * 0.04),
                with: .color(primary)
            )
            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.14, y: h * 0.48, width: w * 0.58, height: h * 0.20
                ), cornerRadius: w * 0.04),
                with: .color(primary.opacity(0.55))
            )
            context.fill(
                Path(roundedRect: CGRect(
                    x: w * 0.14, y: h * 0.74, width: w * 0.58, height: h * 0.20
                ), cornerRadius: w * 0.04),
                with: .color(primary.opacity(0.28))
            )

            context.fill(
                Path(ellipseIn: CGRect(
                    x: w * 0.78 - w * 0.021, y: h * 0.41 - w * 0.021,
                    width: w * 0.042, height: w * 0.042
                )),
                with: .color(Color.white.opacity(0.9))
            )
        }
        .frame(width: 152, height: 122)
    }
}

// MARK: - 閫氱敤绌虹姸鎬?
/// 缁熶竴鐨勭┖鐘舵€侊細鍦嗚鏂瑰潡鍥炬爣 + 鏍囬 + 璇存槑銆?struct EmptyStateView<Action: View>: View {

    let systemIcon: String
    let title: String
    var message: String? = nil
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Aurora.brand.tint(0.10))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: systemIcon)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Aurora.brand)
                )
            Spacer().frame(height: 16)
            Text(title)
                .font(AuroraFont.titleLarge)
                .foregroundStyle(Aurora.ink)
            if let message {
                Spacer().frame(height: 4)
                Text(message)
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer().frame(height: 14)
            action()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(systemIcon: String, title: String, message: String? = nil) {
        self.init(systemIcon: systemIcon, title: title, message: message) { EmptyView() }
    }
}
