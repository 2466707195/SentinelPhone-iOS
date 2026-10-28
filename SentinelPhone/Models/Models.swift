import Foundation
import CoreGraphics

// === 车载哨兵 · 手机端数据模型 ===
// 与车机端 /api/v1/* 的 JSON 对齐。字段尽量可选，
// 这样车机升级新增字段、老版本 App 也不会 decode 失败。

struct SentinelDevice: Codable {
    var id: String? = nil
    var name: String? = nil
    var model: String? = nil
    var version: String? = nil
    var ip: String? = nil
    var port: Int? = nil
    var lanUrl: String? = nil
}

struct SentinelChannel: Codable, Identifiable {
    var id: String = ""
    var name: String? = nil
    var short: String? = nil
    var online: Bool? = nil
    var width: Int? = nil
    var height: Int? = nil
    var fps: Double? = nil
    var source: String? = nil
    var sourceLabel: String? = nil
    var resolution: String? = nil
    var enabled: Bool? = nil
    var error: String? = nil
    var lastFrameAt: Double? = nil
    var recording: Bool? = nil

    var isOnline: Bool { online ?? false }
    var displayName: String { name ?? "机位" }
    var displayShort: String { short ?? String(displayName.prefix(1)) }
    var displayResolution: String {
        if let w = width, let h = height, w > 0, h > 0 { return "\(w)×\(h)" }
        return resolution ?? "—"
    }
    var displayFPS: String {
        guard let fps, fps > 0 else { return "—" }
        return String(format: "%.0f", fps)
    }
}

struct SentinelStorageInfo: Codable {
    var totalBytes: Double? = nil
    var freeBytes: Double? = nil
    var recordBytes: Double? = nil
    var retentionDays: Int? = nil
}

struct SentinelMetrics: Codable {
    var bitrateKbps: Double? = nil
    var onlineChannels: Int? = nil
    var totalChannels: Int? = nil
    var recordFps: Int? = nil
    var relayFps: Int? = nil
}

struct SentinelRelayInfo: Codable {
    var enabled: Bool? = nil
    var connected: Bool? = nil
    var url: String? = nil
    var message: String? = nil
}

struct SentinelNetworkInfo: Codable {
    var lan: Bool? = nil
    var ip: String? = nil
    var port: Int? = nil
    var lanUrl: String? = nil
    /// 车机所有可直连的本机 IPv4（含 Tailscale 100.x），手机端会挨个探测。
    var ips: [String]? = nil
}

struct SentinelSettingsInfo: Codable {
    var retentionDays: Int? = nil
    var autoRecord: Bool? = nil
    var bootStart: Bool? = nil
    var motionEnabled: Bool? = nil
    var motionSensitivity: Double? = nil
    var shockEnabled: Bool? = nil
    var liveFps: Int? = nil
    var liveWidth: Int? = nil
    var liveQuality: Int? = nil
    var recordFps: Int? = nil
    var recordWidth: Int? = nil
    var recordQuality: Int? = nil
    var relayFps: Int? = nil
    var relayWidth: Int? = nil
}

struct SentinelStatus: Codable {
    var device: SentinelDevice? = nil
    var recording: Bool? = nil
    var startedAt: Double? = nil
    var durationMs: Double? = nil
    var uptimeSec: Double? = nil
    var storage: SentinelStorageInfo? = nil
    var metrics: SentinelMetrics? = nil
    var channels: [SentinelChannel]? = nil
    var relay: SentinelRelayInfo? = nil
    var network: SentinelNetworkInfo? = nil
    var settings: SentinelSettingsInfo? = nil
    var sessions: Int? = nil
    var events: Int? = nil

    var isRecording: Bool { recording ?? false }
    var channelsOrEmpty: [SentinelChannel] { channels ?? [] }
    var onlineCount: Int { channelsOrEmpty.filter(\.isOnline).count }
    var totalCount: Int { channelsOrEmpty.count }
    var deviceName: String { device?.name ?? "车载哨兵" }
    var bitrateText: String {
        let kbps = metrics?.bitrateKbps ?? 0
        if kbps >= 1000 { return String(format: "%.1f Mbps", kbps / 1000) }
        return "\(Int(kbps)) Kbps"
    }
    var freeText: String { formatBytes(storage?.freeBytes ?? 0) }
    var recordText: String { formatBytes(storage?.recordBytes ?? 0) }
    var retentionText: String { "\(settings?.retentionDays ?? storage?.retentionDays ?? 3) 天" }
    var recordingDuration: TimeInterval {
        if let durationMs, durationMs > 0 { return durationMs / 1000 }
        guard isRecording, let startedAt, startedAt > 0 else { return 0 }
        return max(0, Date().timeIntervalSince1970 - startedAt / 1000)
    }
    var uptimeText: String {
        let seconds = Int(uptimeSec ?? 0)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分"
    }
}

struct RecordingSession: Codable, Identifiable, Hashable {
    var id: String = ""
    var runId: String? = nil
    var channelId: String? = nil
    var channelName: String? = nil
    var startedAt: Double? = nil
    var endedAt: Double? = nil
    var durationMs: Double? = nil
    var frameCount: Int? = nil
    var intervalMs: Double? = nil
    var fps: Double? = nil
    var width: Int? = nil
    var height: Int? = nil
    var bytes: Double? = nil
    var recording: Bool? = nil
    var previewUrl: String? = nil
    var frameUrlPattern: String? = nil
    var frames: Int? = nil

    var displayName: String { channelName ?? "机位" }
    var startDate: Date { Date(timeIntervalSince1970: (startedAt ?? 0) / 1000) }
    var duration: TimeInterval {
        if let durationMs, durationMs > 0 { return durationMs / 1000 }
        guard let startedAt, let endedAt, endedAt > startedAt else { return 0 }
        return (endedAt - startedAt) / 1000
    }
    var durationText: String { formatDuration(duration) }
    var sizeText: String { formatBytes(bytes ?? 0) }
    var count: Int { frameCount ?? frames ?? 0 }
    var interval: TimeInterval {
        let ms = intervalMs ?? 33
        return max(0.016, ms / 1000)
    }
    var isActive: Bool { (endedAt ?? 0) <= 0 }
    var resolutionText: String {
        guard let w = width, let h = height, w > 0, h > 0 else { return "—" }
        return "\(w)×\(h)"
    }
}

struct EventClip: Codable, Hashable {
    var sessionId: String? = nil
    var frameIndex: Int? = nil
    var fps: Int? = nil
    var count: Int? = nil
}

struct SentinelEvent: Codable, Identifiable, Hashable {
    var id: String = ""
    var ts: Double? = nil
    var kind: String? = nil
    var severity: Int? = nil
    var title: String? = nil
    var detail: String? = nil
    var channelId: String? = nil
    var channelName: String? = nil
    var runId: String? = nil
    var frameIndex: Int? = nil
    var snapshotUrl: String? = nil
    var thumbUrl: String? = nil
    var hasSnapshot: Bool? = nil
    var clip: EventClip? = nil

    var date: Date { Date(timeIntervalSince1970: (ts ?? 0) / 1000) }
    var kindLabel: String {
        switch kind {
        case "MOTION": return "移动侦测"
        case "SHOCK": return "车辆震动"
        case "CAMERA_OFFLINE": return "机位离线"
        case "MANUAL": return "手动抓拍"
        default: return "事件"
        }
    }
    var kindIcon: String {
        switch kind {
        case "MOTION": return "figure.walk.motion"
        case "SHOCK": return "waveform.path.ecg"
        case "CAMERA_OFFLINE": return "wifi.slash"
        case "MANUAL": return "camera.fill"
        default: return "bell.fill"
        }
    }
    var severityLabel: String {
        switch severity ?? 1 {
        case 3: return "紧急"
        case 2: return "重要"
        default: return "提示"
        }
    }
    var displayTitle: String { title ?? kindLabel }
    var displayDetail: String { detail ?? "" }
    var displayChannel: String { channelName ?? "车机" }
    var clipSessionId: String? {
        if let id = clip?.sessionId, !id.isEmpty { return id }
        guard let runId, let channelId, !runId.isEmpty else { return nil }
        return "\(runId)_\(channelId)"
    }
    var playbackIndex: Int { clip?.frameIndex ?? frameIndex ?? 0 }
}

struct SentinelConfigSnapshot: Codable {
    var deviceName: String? = nil
    var port: Int? = nil
    var relayEnabled: Bool? = nil
    var relayUrl: String? = nil
    var relayDeviceId: String? = nil
    var recordFps: Int? = nil
    var recordWidth: Int? = nil
    var retentionDays: Int? = nil
    var relayFps: Int? = nil
    var channels: [SentinelChannel]? = nil
}

struct RelayDevice: Codable, Identifiable {
    var id: String
    var name: String? = nil
    var online: Bool? = nil
    var lastSeen: Double? = nil
    var status: SentinelStatus? = nil
    var version: String? = nil

    var displayName: String { name ?? id }
    var isOnline: Bool { online ?? (status != nil) }
}

struct DiscoveredDevice: Identifiable, Hashable {
    var id: String
    var name: String
    var host: String
    var port: Int

    var urlText: String { "\(host):\(port)" }
}

enum ConnectionMode: String, CaseIterable, Identifiable {
    case lan
    case relay
    case demo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lan: return "局域网"
        case .relay: return "远程中继"
        case .demo: return "演示"
        }
    }
    var icon: String {
        switch self {
        case .lan: return "wifi"
        case .relay: return "antenna.radiowaves.left.and.right"
        case .demo: return "sparkles"
        }
    }
}

enum SentinelConnection: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
    case demo

    var title: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .failed(let message): return message
        case .demo: return "演示数据"
        }
    }
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    var isDemo: Bool {
        if case .demo = self { return true }
        return false
    }
}

// MARK: - 格式化

func formatBytes(_ value: Double) -> String {
    if value <= 0 { return "0 B" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = value
    var index = 0
    while v >= 1024 && index < units.count - 1 {
        v /= 1024
        index += 1
    }
    if index == 0 { return "\(Int(v)) \(units[index])" }
    return String(format: "%.1f %@", v, units[index])
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h) 小时 \(m) 分" }
    if m > 0 { return "\(m) 分 \(s) 秒" }
    return "\(s) 秒"
}

func formatShortDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

func formatClock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}

func formatDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd"
    return formatter.string(from: date)
}

func formatRelative(_ date: Date) -> String {
    let delta = Date().timeIntervalSince(date)
    if delta < 60 { return "刚刚" }
    if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
    if delta < 86400 { return "\(Int(delta / 3600)) 小时前" }
    if delta < 172800 { return "昨天 \(formatClock(date))" }
    return formatTime(date)
}
