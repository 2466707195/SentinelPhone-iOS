import Foundation
import UIKit
import Combine

/// 手机端唯一的连接状态中心：演示 / 局域网 / 中继 三种数据源都汇总到这里。
@MainActor
final class SentinelStore: ObservableObject {

    // MARK: - 发布状态

    @Published private(set) var mode: ConnectionMode = .demo
    @Published private(set) var connection: SentinelConnection = .demo
    @Published private(set) var status: SentinelStatus?
    @Published private(set) var frames: [String: UIImage] = [:]
    @Published private(set) var frameDates: [String: Date] = [:]
    @Published private(set) var channelErrors: [String: String] = [:]
    @Published private(set) var sessions: [RecordingSession] = []
    @Published private(set) var events: [SentinelEvent] = []
    @Published private(set) var discoveries: [DiscoveredDevice] = []
    @Published private(set) var relayDevices: [RelayDevice] = []
    @Published private(set) var relayLoading = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    // 设备页表单（可编辑）
    @Published var lanAddress: String = ""
    @Published var relayURL: String = "ws://8.160.187.185:8722"
    @Published var relayKey: String = "NhiRFzlTf5RcWDXh7rnypJK0GefI"
    @Published var relayDeviceID: String = ""
    @Published var autoRecord: Bool = false
    @Published private(set) var localSettings = SentinelSettingsInfo()

    /// 事件详情里点「在回放中查看」时给回放页的提示。
    @Published var requestedSessionID: String?

    // MARK: - 私有

    private var lan: LanClient?
    private var streams: [String: MJPEGStream] = [:]
    private var relay: RelayClient?
    private let discovery = LanDiscovery()
    private var refreshTask: Task<Void, Never>?
    private var demoStart: Double = 0
    private var lanFailures = 0
    private var relayTick = 0
    private var started = false
    private var imageCache: [String: UIImage] = [:]
    private var imageOrder: [String] = []

    init() {
        demoStart = Date().timeIntervalSince1970 * 1000 - (2 * 3600 + 2 * 60) * 1000
        status = DemoData.status(startedAt: demoStart)
        sessions = DemoData.sessions()
        events = DemoData.events()
        discovery.onChange = { [weak self] devices in
            Task { @MainActor in
                self?.discoveries = devices
            }
        }
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        // 不再进入演示模式：未连接就显示未连接，已连接只显示真实数据
        stopNetwork()
        mode = .lan
        connection = .idle
        status = nil
        sessions = []
        events = []
        lastError = nil
        startDiscovery()
        startRefreshLoop()
    }

    func refreshNow() {
        switch mode {
        case .demo:
            enterDemo()
        case .lan:
            connectLAN()
        case .relay:
            connectRelay()
        }
    }

    func setMode(_ newMode: ConnectionMode) {
        guard newMode != mode else {
            if newMode == .lan { discovery.start() }
            return
        }
        switch newMode {
        case .demo:
            enterDemo()
        case .lan:
            stopNetwork()
            mode = .lan
            connection = .idle
            status = nil
            sessions = []
            events = []
            lastError = nil
            discovery.start()
        case .relay:
            stopNetwork()
            mode = .relay
            connection = .idle
            status = nil
            sessions = []
            events = []
            lastError = nil
        }
    }

    private func enterDemo() {
        stopNetwork()
        mode = .demo
        connection = .demo
        status = DemoData.status(startedAt: demoStart)
        sessions = DemoData.sessions()
        events = DemoData.events()
        lastError = nil
        startRefreshLoop()
    }

    private func stopNetwork() {
        lan = nil
        stopStreams()
        relay?.disconnect()
        relay = nil
        discovery.stop()
        refreshTask?.cancel()
        refreshTask = nil
        connection = .idle
        frames.removeAll()
        frameDates.removeAll()
        channelErrors.removeAll()
        imageCache.removeAll()
        imageOrder.removeAll()
    }

    func disconnect() {
        let current = mode
        stopNetwork()
        mode = current
        connection = .idle
        lastError = nil
        status = current == .demo ? DemoData.status(startedAt: demoStart) : nil
        sessions = current == .demo ? DemoData.sessions() : []
        events = current == .demo ? DemoData.events() : []
        if current == .demo { enterDemo() }
    }

    // MARK: - 局域网

    func connectLAN(address: String? = nil) {
        let raw = (address ?? lanAddress).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            connection = .failed("请先填写车机 IP，或从下面的设备里选一个")
            return
        }
        guard let client = LanClient(rawAddress: raw) else {
            connection = .failed("地址格式不正确")
            return
        }
        stopNetwork()
        mode = .lan
        lanAddress = raw
        lan = client
        connection = .connecting
        lastError = nil
        discovery.stop()

        Task { @MainActor in
            do {
                let status = try await client.status()
                guard self.lan === client else { return }
                self.apply(status)
                self.connection = .connected
                self.lanFailures = 0
                self.startStreams(with: status)
                self.startRefreshLoop()
                await self.refreshLists()
            } catch {
                guard self.lan === client else { return }
                self.connection = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
        }
    }

    private func refreshLAN() async {
        guard let lan else { return }
        do {
            let status = try await lan.status()
            guard self.lan === lan else { return }
            self.apply(status)
            self.connection = .connected
            self.lanFailures = 0
            if self.streams.isEmpty {
                self.startStreams(with: status)
            }
        } catch {
            self.lanFailures += 1
            if self.lanFailures >= 3 {
                guard self.lan === lan else { return }
                self.connection = .failed("车机无响应，请检查同一 Wi-Fi")
                self.stopStreams()
            }
        }
    }

    private func startStreams(with status: SentinelStatus) {
        guard let lan else { return }
        stopStreams()
        for channel in status.channelsOrEmpty {
            guard channel.isOnline, channel.enabled != false,
                  let url = lan.streamURL(channelID: channel.id) else { continue }
            let channelID = channel.id
            let stream = MJPEGStream(
                url: url,
                channelID: channelID,
                onFrame: { [weak self] image in
                    Task { @MainActor in
                        guard let self else { return }
                        self.frames[channelID] = image
                        self.frameDates[channelID] = Date()
                        self.channelErrors.removeValue(forKey: channelID)
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.channelErrors[channelID] = message
                    }
                }
            )
            streams[channelID] = stream
            stream.start()
        }
    }

    private func stopStreams() {
        streams.values.forEach { $0.stop() }
        streams.removeAll()
    }

    func startDiscovery() {
        discovery.start()
    }

    func stopDiscovery() {
        discovery.stop()
    }

    // MARK: - 远程中继

    func loadRelayDevices() {
        let base = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            lastError = "请先填写中继地址"
            connection = .failed("请先填写中继地址")
            return
        }
        relayLoading = true
        Task { @MainActor in
            defer { self.relayLoading = false }
            do {
                let devices = try await RelayDirectory.fetchDevices(base: base, key: relayKey)
                self.relayDevices = devices.sorted {
                    if $0.isOnline != $1.isOnline { return $0.isOnline && !$1.isOnline }
                    return $0.id.localizedStandardCompare($1.id) == .orderedAscending
                }
                if self.relayDeviceID.isEmpty, let first = self.relayDevices.first {
                    self.relayDeviceID = first.id
                }
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
                self.connection = .failed(error.localizedDescription)
            }
        }
    }

    func connectRelay() {
        let base = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = relayDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            connection = .failed("请填写中继地址")
            return
        }
        guard !device.isEmpty else {
            connection = .failed("请选择或填写车机 ID")
            return
        }

        stopNetwork()
        mode = .relay
        connection = .connecting
        lastError = nil

        let client = RelayClient()
        relay = client
        client.onState = { [weak self] connected, message in
            Task { @MainActor in
                guard let self, self.relay === client else { return }
                if connected {
                    self.connection = .connected
                    self.lastError = nil
                    self.startRefreshLoop()
                    await self.refreshLists()
                } else if let message, !message.isEmpty, !message.contains("正在") {
                    self.connection = .failed(message)
                } else {
                    self.connection = .idle
                }
            }
        }
        client.onStatus = { [weak self] status in
            Task { @MainActor in
                guard let self, self.relay === client else { return }
                self.apply(status)
                self.connection = .connected
            }
        }
        client.onFrame = { [weak self] channel, image in
            Task { @MainActor in
                guard let self, self.relay === client else { return }
                self.frames[channel] = image
                self.frameDates[channel] = Date()
                self.channelErrors.removeValue(forKey: channel)
            }
        }

        do {
            try client.connect(base: base, key: relayKey, deviceID: device)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    private func refreshRelayStatus() async {
        guard let relay, relay.isConnected else { return }
        relayTick += 1
        guard relayTick % 2 == 0 else { return }
        guard let data = try? await relay.requestJSONData(path: "/api/v1/status"),
              let status = try? JSONDecoder().decode(SentinelStatus.self, from: data) else { return }
        apply(status)
        connection = .connected
    }

    // MARK: - 列表刷新

    private func refreshLists() async {
        if mode == .lan, let lan {
            if let newSessions = try? await lan.sessions() {
                sessions = newSessions.sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
            }
            if let newEvents = try? await lan.events() {
                events = newEvents.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
            }
        } else if mode == .relay, let relay, relay.isConnected {
            struct SessionsResponse: Decodable { var sessions: [RecordingSession]? }
            struct EventsResponse: Decodable { var events: [SentinelEvent]? }
            if let data = try? await relay.requestJSONData(path: "/api/v1/sessions"),
               let response = try? JSONDecoder().decode(SessionsResponse.self, from: data) {
                sessions = (response.sessions ?? []).sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
            }
            if let data = try? await relay.requestJSONData(path: "/api/v1/events"),
               let response = try? JSONDecoder().decode(EventsResponse.self, from: data) {
                events = (response.events ?? []).sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
            }
        }
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.mode == .demo {
                    self.status = DemoData.status(startedAt: self.demoStart)
                    continue
                }
                guard self.connection.isConnected else { continue }
                if self.mode == .lan {
                    await self.refreshLAN()
                } else if self.mode == .relay {
                    await self.refreshRelayStatus()
                }
                tick += 1
                if tick % 5 == 0 {
                    await self.refreshLists()
                }
            }
        }
    }

    private func apply(_ status: SentinelStatus) {
        self.status = status
        lastError = nil
        if let settings = status.settings {
            localSettings = settings
            autoRecord = settings.autoRecord ?? autoRecord
        }
        if lanAddress.isEmpty, let url = status.device?.lanUrl, !url.isEmpty {
            lanAddress = url.replacingOccurrences(of: "http://", with: "")
        }
    }

    // MARK: - 控制

    func control(_ action: String) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { self.isBusy = false }
            switch self.mode {
            case .demo:
                self.demoControl(action)
            case .lan:
                if let lan = self.lan {
                    _ = try? await lan.sendControl(action)
                    await self.refreshLAN()
                    await self.refreshLists()
                }
            case .relay:
                self.relay?.sendCommand(action)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.refreshRelayStatus()
            }
        }
    }

    private func demoControl(_ action: String) {
        guard var status else { return }
        switch action {
        case "start_record":
            status.recording = true
            let now = Date().timeIntervalSince1970 * 1000
            status.startedAt = now
            status.durationMs = 0
            self.status = status
        case "stop_record":
            status.recording = false
            status.durationMs = status.recordingDuration * 1000
            self.status = status
        case "snapshot":
            let now = Date().timeIntervalSince1970 * 1000
            let channel = status.channelsOrEmpty.first
            let event = SentinelEvent(
                id: "demo-snap-\(Int(now))",
                ts: now,
                kind: "MANUAL",
                severity: 1,
                title: "手动抓拍",
                detail: "演示模式：已记录一次手动抓拍。",
                channelId: channel?.id ?? "front",
                channelName: channel?.displayName ?? "前视",
                runId: "demo_run",
                frameIndex: 0,
                snapshotUrl: nil,
                thumbUrl: nil,
                hasSnapshot: true,
                clip: nil
            )
            events.insert(event, at: 0)
        case "cleanup":
            sessions = sessions.filter { $0.startDate > Date().addingTimeInterval(-3 * 86400) }
        default:
            break
        }
    }

    func toggleRecording() {
        control((status?.isRecording ?? false) ? "stop_record" : "start_record")
    }

    /// 自动开始录制：演示模式只切本地状态，真实连接同步到车机端。
    func setAutoRecord(_ enabled: Bool) {
        autoRecord = enabled
        var settings = localSettings
        settings.autoRecord = enabled
        localSettings = settings
        if var status {
            status.settings = settings
            self.status = status
        }
        guard mode != .demo else { return }
        Task { @MainActor in
            switch self.mode {
            case .lan:
                if let lan = self.lan {
                    _ = try? await lan.sendControl("set_auto_record", payload: ["enabled": enabled])
                    await self.refreshLAN()
                }
            case .relay:
                self.relay?.sendCommand("set_auto_record", payload: ["enabled": enabled])
                try? await Task.sleep(nanoseconds: 400_000_000)
                await self.refreshRelayStatus()
            case .demo:
                break
            }
        }
    }

    /// 删除一段录像；车机端正在录制的机位不允许删。
    func deleteSession(id: String) {
        Task { @MainActor in
            switch self.mode {
            case .demo:
                self.sessions.removeAll { $0.id == id }
            case .lan:
                if let lan = self.lan {
                    _ = try? await lan.sendControl("delete_session", payload: ["sessionId": id])
                    await self.refreshLists()
                }
            case .relay:
                self.relay?.sendCommand("delete_session", payload: ["sessionId": id])
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.refreshLists()
            }
        }
    }

    /// 统一配置更新：预览帧率/清晰度、录制帧率/清晰度/画质等。
    func updateConfig(_ values: [String: Any]) {
        // 先本地生效，开关/滑杆立刻响应；随后再同步到车机
        applyLocalConfig(values)
        guard mode != .demo else { return }
        Task { @MainActor in
            switch self.mode {
            case .lan:
                if let lan = self.lan {
                    _ = try? await lan.sendControl("update_config", payload: values)
                    await self.refreshLAN()
                    await self.refreshLists()
                }
            case .relay:
                self.relay?.sendCommand("update_config", payload: values)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self.refreshRelayStatus()
            case .demo:
                break
            }
        }
    }

    private func applyLocalConfig(_ values: [String: Any]) {
        var settings = localSettings
        if let v = values["liveFps"] as? Int { settings.liveFps = v }
        if let v = values["liveWidth"] as? Int { settings.liveWidth = v }
        if let v = values["liveQuality"] as? Int { settings.liveQuality = v }
        if let v = values["recordFps"] as? Int { settings.recordFps = v }
        if let v = values["recordWidth"] as? Int { settings.recordWidth = v }
        if let v = values["recordQuality"] as? Int { settings.recordQuality = v }
        if let v = values["retentionDays"] as? Int { settings.retentionDays = v }
        if let v = values["motionEnabled"] as? Bool { settings.motionEnabled = v }
        if let v = values["motionSensitivity"] as? Double { settings.motionSensitivity = v }
        if let v = values["shockEnabled"] as? Bool { settings.shockEnabled = v }
        if let v = values["relayFps"] as? Int { settings.relayFps = v }
        if let v = values["relayWidth"] as? Int { settings.relayWidth = v }
        if let v = values["autoRecord"] as? Bool {
            settings.autoRecord = v
            autoRecord = v
        }
        localSettings = settings
        if var status {
            status.settings = settings
            self.status = status
        }
    }

    /// 导出一段录像为 zip，返回临时文件 URL。
    func exportSession(_ session: RecordingSession) async -> URL? {
        guard mode != .demo else { return nil }
        do {
            let data: Data
            if mode == .lan, let lan {
                data = try await lan.data(path: "/api/v1/sessions/\(session.id)/export.zip")
            } else if mode == .relay, let relay {
                data = try await relay.requestData(path: "/api/v1/sessions/\(session.id)/export.zip")
            } else {
                return nil
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(session.id).zip")
            try data.write(to: url)
            return url
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 设置值

    var liveFps: Int { localSettings.liveFps ?? 60 }
    var liveWidth: Int { localSettings.liveWidth ?? 640 }
    var liveQuality: Int { localSettings.liveQuality ?? 55 }
    var recordFps: Int { localSettings.recordFps ?? 30 }
    var recordWidth: Int { localSettings.recordWidth ?? 640 }
    var recordQuality: Int { localSettings.recordQuality ?? 62 }
    var retentionDays: Int { localSettings.retentionDays ?? 3 }
    var motionEnabled: Bool { localSettings.motionEnabled ?? true }
    var shockEnabled: Bool { localSettings.shockEnabled ?? true }
    var motionSensitivity: Double { localSettings.motionSensitivity ?? 0.08 }

    // MARK: - 图片

    func image(path: String?) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = imageCache[path] { return cached }
        guard connection.isConnected else { return nil }
        do {
            let image: UIImage
            if mode == .lan, let lan {
                image = try await lan.image(path: path)
            } else if mode == .relay, let relay {
                image = try await relay.requestImage(path: path)
            } else {
                return nil
            }
            cacheImage(image, path: path)
            return image
        } catch {
            return nil
        }
    }

    func thumbnail(for session: RecordingSession) async -> UIImage? {
        if mode == .demo { return nil }
        let path = session.previewUrl ?? "/api/v1/sessions/\(session.id)/preview.jpg"
        return await image(path: path)
    }

    func snapshot(for event: SentinelEvent) async -> UIImage? {
        if mode == .demo { return nil }
        let path = event.thumbUrl ?? event.snapshotUrl ?? "/api/v1/events/\(event.id)/snapshot.jpg"
        return await image(path: path)
    }

    func playbackFrame(session: RecordingSession, index: Int) async -> UIImage? {
        if mode == .demo { return nil }
        let last = max(0, session.count - 1)
        let safeIndex = min(max(0, index), last)
        if mode == .relay, let relay, relay.isConnected {
            return try? await relay.requestFrame(sessionID: session.id, index: safeIndex)
        }
        let pattern = session.frameUrlPattern ?? "/api/v1/sessions/\(session.id)/frames/{index}.jpg"
        return await image(path: pattern.replacingOccurrences(of: "{index}", with: "\(safeIndex)"))
    }

    private func cacheImage(_ image: UIImage, path: String) {
        imageCache[path] = image
        imageOrder.removeAll { $0 == path }
        imageOrder.append(path)
        while imageOrder.count > 120 {
            let old = imageOrder.removeFirst()
            imageCache.removeValue(forKey: old)
        }
    }

    func session(id: String?) -> RecordingSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    var isDemo: Bool { mode == .demo }
    var deviceName: String { status?.deviceName ?? "车载哨兵" }
    var isConnected: Bool { connection.isConnected }
}
