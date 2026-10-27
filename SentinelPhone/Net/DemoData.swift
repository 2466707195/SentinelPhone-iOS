import Foundation

/// 演示数据：没有连接车机时也能完整看到界面、回放和事件。
enum DemoData {

    static let channels: [SentinelChannel] = [
        SentinelChannel(
            id: "front", name: "前视", short: "前", online: true,
            width: 1920, height: 1080, fps: 25,
            source: "CAMERA2", sourceLabel: "内置主摄",
            resolution: "1920x1080", enabled: true, error: "",
            lastFrameAt: 0, recording: true
        ),
        SentinelChannel(
            id: "rear", name: "后视", short: "后", online: true,
            width: 1280, height: 720, fps: 25,
            source: "UVC", sourceLabel: "外接 USB",
            resolution: "1280x720", enabled: true, error: "",
            lastFrameAt: 0, recording: true
        ),
        SentinelChannel(
            id: "left", name: "左侧", short: "左", online: true,
            width: 1280, height: 720, fps: 20,
            source: "MJPEG", sourceLabel: "网络摄像头",
            resolution: "1280x720", enabled: true, error: "",
            lastFrameAt: 0, recording: true
        ),
        SentinelChannel(
            id: "right", name: "右侧", short: "右", online: true,
            width: 1280, height: 720, fps: 20,
            source: "SNAPSHOT", sourceLabel: "快照轮询",
            resolution: "1280x720", enabled: true, error: "",
            lastFrameAt: 0, recording: true
        )
    ]

    static func status(startedAt: Double? = nil) -> SentinelStatus {
        let now = Date().timeIntervalSince1970 * 1000
        let start = startedAt ?? (now - (2 * 3600 + 2 * 60) * 1000)
        return SentinelStatus(
            device: SentinelDevice(
                id: "demo-car",
                name: "车载哨兵 · 演示",
                model: "Aurora Car",
                version: "1.0.0",
                ip: "192.168.1.23",
                port: 8720,
                lanUrl: "http://192.168.1.23:8720"
            ),
            recording: true,
            startedAt: start,
            durationMs: max(0, now - start),
            uptimeSec: 9_240,
            storage: SentinelStorageInfo(
                totalBytes: 128 * 1024 * 1024 * 1024,
                freeBytes: 44.6 * 1024 * 1024 * 1024,
                recordBytes: 61.2 * 1024 * 1024 * 1024,
                retentionDays: 3
            ),
            metrics: SentinelMetrics(
                bitrateKbps: 12_300,
                onlineChannels: 4,
                totalChannels: 4,
                recordFps: 2,
                relayFps: 2
            ),
            channels: channels,
            relay: SentinelRelayInfo(
                enabled: true,
                connected: false,
                url: "wss://relay.example.com/ws",
                message: "演示模式不会连接中继"
            ),
            network: SentinelNetworkInfo(
                lan: true,
                ip: "192.168.1.23",
                port: 8720,
                lanUrl: "http://192.168.1.23:8720"
            ),
            settings: SentinelSettingsInfo(
                retentionDays: 3,
                autoRecord: true,
                motionEnabled: true,
                shockEnabled: true
            ),
            sessions: 6,
            events: 6
        )
    }

    static func sessions() -> [RecordingSession] {
        let now = Date().timeIntervalSince1970 * 1000
        let day: Double = 24 * 3600 * 1000
        let rows: [(String, String, Double, Double, Int, Int, Int, Double)] = [
            ("demo_run_front", "前视", now - 1.2 * 3600 * 1000, 204_000, 408, 1920, 1080, 96 * 1024 * 1024),
            ("demo_run_rear", "后视", now - 2.8 * 3600 * 1000, 130_000, 260, 1280, 720, 62 * 1024 * 1024),
            ("demo_run_left", "左侧", now - 4.0 * 3600 * 1000, 108_000, 216, 1280, 720, 48 * 1024 * 1024),
            ("demo_run_right", "右侧", now - day + 3.5 * 3600 * 1000, 252_000, 504, 1280, 720, 110 * 1024 * 1024),
            ("demo_run_front2", "前视", now - day + 1.1 * 3600 * 1000, 176_000, 352, 1920, 1080, 84 * 1024 * 1024),
            ("demo_run_rear2", "后视", now - 2 * day + 2.0 * 3600 * 1000, 90_000, 180, 1280, 720, 42 * 1024 * 1024)
        ]
        return rows.map { row in
            RecordingSession(
                id: row.0,
                runId: "demo_run",
                channelId: channelID(for: row.1),
                channelName: row.1,
                startedAt: row.2,
                endedAt: row.2 + row.3,
                durationMs: row.3,
                frameCount: row.4,
                intervalMs: 500,
                fps: 2,
                width: row.5,
                height: row.6,
                bytes: row.7,
                recording: false,
                previewUrl: nil,
                frameUrlPattern: nil,
                frames: row.4
            )
        }
    }

    static func events() -> [SentinelEvent] {
        let now = Date().timeIntervalSince1970 * 1000
        let day: Double = 24 * 3600 * 1000
        let rows: [(String, Double, String, Int, String, String, String, String)] = [
            ("demo-ev-1", now - 2 * 60 * 1000, "MOTION", 2, "车辆附近检测到移动",
             "前视画面持续 8 秒有行人经过，已保存事件前后各 20 秒。", "front", "前视"),
            ("demo-ev-2", now - 18 * 60 * 1000, "SHOCK", 3, "检测到明显震动",
             "停车状态下发生连续两次震动，请检查车辆周围情况。", "rear", "后视"),
            ("demo-ev-3", now - 58 * 60 * 1000, "CAMERA_OFFLINE", 1, "右侧机位短暂离线",
             "网络摄像头 3 秒没有返回画面，已自动恢复。", "right", "右侧"),
            ("demo-ev-4", now - 2.1 * 3600 * 1000, "MANUAL", 1, "手动抓拍",
             "你在实时画面里抓拍了一张前视照片。", "front", "前视"),
            ("demo-ev-5", now - 5.2 * 3600 * 1000, "MOTION", 2, "后视检测到移动",
             "画面右下角有车辆驶过，持续约 5 秒。", "rear", "后视"),
            ("demo-ev-6", now - day + 6.4 * 3600 * 1000, "SHOCK", 2, "停车震动",
             "车门关闭产生的轻微震动，记录为提示级事件。", "left", "左侧")
        ]
        return rows.map { row in
            SentinelEvent(
                id: row.0,
                ts: row.1,
                kind: row.2,
                severity: row.3,
                title: row.4,
                detail: row.5,
                channelId: channelID(for: row.7),
                channelName: row.7,
                runId: "demo_run",
                frameIndex: 40,
                snapshotUrl: nil,
                thumbUrl: nil,
                hasSnapshot: true,
                clip: EventClip(sessionId: "demo_run_\(channelID(for: row.7))", frameIndex: 40, fps: 2, count: 80)
            )
        }
    }

    private static func channelID(for name: String) -> String {
        switch name {
        case "后视": return "rear"
        case "左侧": return "left"
        case "右侧": return "right"
        default: return "front"
        }
    }

    static func channelColorIndex(_ channelID: String) -> Int {
        switch channelID {
        case "rear": return 1
        case "left": return 2
        case "right": return 3
        default: return 0
        }
    }
}
