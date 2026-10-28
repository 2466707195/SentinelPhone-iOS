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
    /// 最近的换路说明（例如「直连不可用，已切到中继兜底」），给设备页做提示。
    @Published private(set) var transportNote: String = ""

    /// 直连优先：局域网 / Tailscale 直连失败时自动走中继；中继期间持续探测直连，恢复后自动切回。
    @Published var autoFallback: Bool = true

    // 设备页表单（可编辑）
    @Published var lanAddress: String = ""
    @Published var relayURL: String = "wss://relay.duyufeng.cc.cd"
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
    /// 中继兜底期间，后台探测直连是否恢复。
    private var directRecovery: Task<Void, Never>?

    /// 直播帧播放缓冲用的一帧。中继链路会把帧成串送到，直接「来一帧显示一帧」
    /// 就是刷三帧再静止几百毫秒，肉眼就是卡顿。这里先存两帧，再按 20Hz 节拍匀速出帧。
    private struct BufferedFrame {
        let image: UIImage
        let at: Date
    }

    private var frameBuffer: [String: [BufferedFrame]] = [:]
    private var presenter: Task<Void, Never>?
    /// 接收帧率诊断：每秒统计一次，用来区分「网络没给到帧」和「渲染跟不上」。
    private var rxCounts: [String: Int] = [:]
    private var rxBaseline: [String: Int] = [:]
    private var rxBaselineAt = Date()
    @Published private(set) var rxFps: [String: Double] = [:]

    /// 直播画质档位：链路慢就往下掉，稳定了再慢慢升回去。
    /// 只影响手机看直播，不影响车机录像（录像用 record* 配置）。
    private static let streamProfiles: [(width: Int, fps: Int)] = [
        (640, 25), (480, 20), (360, 12), (320, 8)
    ]
    private var streamProfileIndex = 1
    private var lowFpsTicks = 0
    private var highFpsTicks = 0
    private var started = false

    /// 最近连通过的车机地址（局域网 IP、Tailscale IP 混在一起），连接时按顺序挨个探测。
    private static let knownLANKey = "sentinel.lan.known"
    private var knownLANAddresses: [String] = []
    private var imageCache: [String: UIImage] = [:]
    private var imageOrder: [String] = []

    init() {
        demoStart = Date().timeIntervalSince1970 * 1000 - (2 * 3600 + 2 * 60) * 1000
        status = DemoData.status(startedAt: demoStart)
        sessions = DemoData.sessions()
        events = DemoData.events()
        knownLANAddresses = UserDefaults.standard.stringArray(forKey: Self.knownLANKey) ?? []
        if knownLANAddresses.isEmpty {
            // 车机的 Tailscale 地址：出门用 4G 也能直连，不用中继
            knownLANAddresses = ["100.98.157.103:8720"]
        }
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
        // 启动就自动连：直连（局域网 / Tailscale）优先，连不上再走中继兜底
        if !lanCandidates.isEmpty {
            connectLAN()
        }
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
        stopPresenter()
        discovery.stop()
        refreshTask?.cancel()
        refreshTask = nil
        directRecovery?.cancel()
        directRecovery = nil
        connection = .idle
        frames.removeAll()
        frameDates.removeAll()
        channelErrors.removeAll()
        rxCounts.removeAll()
        rxBaseline.removeAll()
        rxFps = [:]
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

    /// 记住连通过的地址（局域网 IP、Tailscale IP 都会记），下次按「最近成功优先」挨个试。
    private func rememberLAN(_ address: String) {
        var list = knownLANAddresses.filter { $0 != address }
        list.insert(address, at: 0)
        knownLANAddresses = Array(list.prefix(6))
        UserDefaults.standard.set(knownLANAddresses, forKey: Self.knownLANKey)
    }

    /// 候选地址：手填的 → 最近连通过的 → 局域网发现的 → 车机上报的所有 IP（含 Tailscale）。
    private var lanCandidates: [String] {
        var list: [String] = []
        let typed = lanAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { list.append(typed) }
        list.append(contentsOf: knownLANAddresses)
        for device in discoveries { list.append(device.urlText) }
        if let info = status?.network {
            let port = info.port ?? 8720
            for ip in info.ips ?? [] { list.append("\(ip):\(port)") }
        }
        var seen = Set<String>()
        let unique = list.filter { !$0.isEmpty && seen.insert($0).inserted }
        return Self.preferLocalFirst(unique)
    }

    /// 同优先级里保持原顺序，但把「同一 Wi-Fi 的私网地址」排在 Tailscale 地址前面：
    /// 两者都能通时走 Wi-Fi，少一层 Tailscale 封装，延迟和 CPU 都更省。
    nonisolated private static func preferLocalFirst(_ list: [String]) -> [String] {
        func score(_ raw: String) -> Int {
            let host = raw.split(separator: ":").first.map(String.init) ?? raw
            if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return 0 }
            if host.hasPrefix("100.") { return 1 }
            return 2
        }
        return list.enumerated()
            .sorted { left, right in
                let a = score(left.element), b = score(right.element)
                return a == b ? left.offset < right.offset : a < b
            }
            .map { $0.element }
    }

    /// 不用管地址是 Wi-Fi 还是 Tailscale：挨个探测，谁能连上就用谁。
    func connectLAN(address: String? = nil) {
        if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let candidates = lanCandidates
        guard !candidates.isEmpty else {
            connection = .failed("请先填写车机 IP，或从下面的设备里选一个")
            return
        }
        Task { @MainActor in
            await self.connectFirstReachable(candidates)
        }
    }

    private func connectFirstReachable(_ candidates: [String]) async {
        stopNetwork()
        mode = .lan
        connection = .connecting
        lastError = nil
        transportNote = ""
        // 连接期间保持 mDNS 在跑，设备列表才不会空着
        discovery.start()

        // 并行探测：串行试 6 个地址最坏要 15 秒，并行只要 2.5 秒
        let reachable = await Self.probeInParallel(candidates)
        for raw in reachable {
            guard let client = LanClient(rawAddress: raw) else { continue }
            do {
                let status = try await client.status()
                self.lan = client
                self.lanAddress = raw
                rememberLAN(raw)
                apply(status)
                connection = .connected
                lanFailures = 0
                transportNote = ""
                startStreams(with: status)
                startRefreshLoop()
                await refreshLists()
                return
            } catch {
                lastError = error.localizedDescription
            }
        }
        connection = .failed("直连不可用（试过 \(candidates.count) 个地址）")
        if autoFallback {
            await fallbackToRelay(reason: "直连不可用（检查 Wi-Fi / Tailscale）")
        }
    }

    /// 并行探测所有候选地址，返回「能连上」的地址，顺序仍按候选优先级。
    nonisolated private static func probeInParallel(_ candidates: [String], timeout: TimeInterval = 2.5) async -> [String] {
        var reachable = Set<String>()
        await withTaskGroup(of: (String, Bool).self) { group in
            for raw in candidates {
                group.addTask {
                    (raw, await LanClient.probe(rawAddress: raw, timeout: timeout))
                }
            }
            for await (raw, ok) in group where ok {
                reachable.insert(raw)
            }
        }
        return candidates.filter { reachable.contains($0) }
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
                if self.autoFallback {
                    await self.fallbackToRelay(reason: "直连中断")
                }
            }
        }
    }

    // MARK: - 兜底与自动切回

    /// 兜底时依次尝试的中继地址：先用用户填的，再退回公网隧道。
    private static let fallbackRelayURL = "wss://relay.duyufeng.cc.cd"

    private var relayBaseCandidates: [String] {
        var list: [String] = []
        let typed = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { list.append(typed) }
        if !list.contains(Self.fallbackRelayURL) { list.append(Self.fallbackRelayURL) }
        return list
    }

    /// 直连不可用时切到中继；连上后后台持续探测直连，恢复就自动切回来。
    private func fallbackToRelay(reason: String) async {
        let typedDevice = relayDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        var chosenBase = ""
        var chosenDevice = ""

        for base in relayBaseCandidates {
            let list = (try? await RelayDirectory.fetchDevices(base: base, key: relayKey)) ?? []
            guard !list.isEmpty else { continue }
            let online = list.filter { $0.isOnline }
            if !typedDevice.isEmpty, list.contains(where: { $0.id == typedDevice }) {
                chosenDevice = typedDevice
            } else if let first = online.first {
                chosenDevice = first.id
            } else {
                continue
            }
            relayDevices = list.sorted {
                if $0.isOnline != $1.isOnline { return $0.isOnline && !$1.isOnline }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            chosenBase = base
            break
        }

        guard !chosenBase.isEmpty, !chosenDevice.isEmpty else {
            connection = .failed("\(reason)，中继上也没有在线车机")
            return
        }

        if relayURL != chosenBase { relayURL = chosenBase }
        if relayDeviceID != chosenDevice { relayDeviceID = chosenDevice }
        transportNote = "\(reason)，已切到中继兜底"
        connectRelay(automatic: true)
    }

    /// 中继兜底期间的后台探测：前 4 轮每 15 秒一次，之后每 60 秒一次。
    private func startDirectRecovery() {
        directRecovery?.cancel()
        directRecovery = Task { @MainActor [weak self] in
            var round = 0
            while !Task.isCancelled {
                let wait: UInt64 = round < 4 ? 15 : 60
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.mode == .relay else { return }
                round += 1

                let candidates = self.lanCandidates
                guard !candidates.isEmpty else { continue }
                let reachable = await Self.probeInParallel(candidates, timeout: 2.0)
                guard let winner = reachable.first else { continue }
                guard self.mode == .relay else { return }

                self.transportNote = "直连已恢复，正在切回"
                self.connectLAN(address: winner)
                return
            }
        }
    }

    private func startStreams(with status: SentinelStatus) {
        guard let lan else { return }
        stopStreams()
        let profile = Self.streamProfiles[streamProfileIndex]
        for channel in status.channelsOrEmpty {
            guard channel.isOnline, channel.enabled != false,
                  let url = lan.streamURL(channelID: channel.id, maxWidth: profile.width, maxFPS: profile.fps) else { continue }
            let channelID = channel.id
            let stream = MJPEGStream(
                url: url,
                channelID: channelID,
                onFrame: { [weak self] image in
                    Task { @MainActor in
                        // 走统一的 30fps 出帧节拍，避免整屏 SwiftUI 每秒被刷 90 次
                        self?.enqueueLiveFrame(channel: channelID, image: image)
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

    func connectRelay(automatic: Bool = false) {
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
        if automatic {
            startDirectRecovery()
        }

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
                self.enqueueLiveFrame(channel: channel, image: image)
            }
        }

        do {
            try client.connect(base: base, key: relayKey, deviceID: device)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    // MARK: - 直播帧平滑播放

    /// 收到新帧先入缓冲。只留最近 3 帧，保证延迟不会越攒越高。
    /// 直连（局域网 / Tailscale）和空中继走同一条路：最多 30fps 出帧，
    /// 不再让每一帧都直接打一次 @Published（3 路 30fps 就是 90 次/秒的整屏重绘，必卡）。
    private func enqueueLiveFrame(channel: String, image: UIImage) {
        var buffer = frameBuffer[channel] ?? []
        buffer.append(BufferedFrame(image: image, at: Date()))
        if buffer.count > 3 {
            buffer.removeFirst(buffer.count - 3)
        }
        frameBuffer[channel] = buffer
        rxCounts[channel, default: 0] += 1
        startPresenter()
    }

    private func startPresenter() {
        guard presenter == nil else { return }
        presenter = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self else { return }
                self.presentLiveFrames()
            }
        }
    }

    private func stopPresenter() {
        presenter?.cancel()
        presenter = nil
        frameBuffer.removeAll()
    }

    /// 每 33ms 放出一帧：
    /// - 缓冲里攒到 2 帧以上，就匀速播放（最多 30fps），帧间隔稳定，肉眼顺滑；
    /// - 只剩 1 帧且已经等了 150ms，就直接放，避免链路慢时画面僵住。
    private func presentLiveFrames() {
        guard !frameBuffer.isEmpty else { return }
        let now = Date()
        for (channel, buffer) in frameBuffer {
            guard let first = buffer.first else { continue }
            let ready = buffer.count >= 2 || now.timeIntervalSince(first.at) > 0.15
            guard ready else { continue }
            var rest = buffer
            rest.removeFirst()
            frameBuffer[channel] = rest
            frames[channel] = first.image
            frameDates[channel] = now
            channelErrors.removeValue(forKey: channel)
        }
    }

    /// 每 2 秒算一次各路「实际收到的帧率」。这就是判断卡在哪一层的分界线：
    /// 接收帧率正常但画面卡 = 渲染问题；接收帧率上不去 = 网络/解码问题。
    private func updateRxFps() {
        let now = Date()
        let seconds = max(now.timeIntervalSince(rxBaselineAt), 0.5)
        var result: [String: Double] = [:]
        for (channel, count) in rxCounts {
            let delta = count - (rxBaseline[channel] ?? 0)
            result[channel] = Double(delta) / seconds
        }
        rxBaseline = rxCounts
        rxBaselineAt = now
        rxFps = result
        adaptStreamProfile()
    }

    /// 按实测接收帧率调整直播画质档位。
    private func adaptStreamProfile() {
        guard mode == .lan, !streams.isEmpty else { return }
        let target = Double(Self.streamProfiles[streamProfileIndex].fps)
        let values = Array(rxFps.values).filter { $0 > 0 }
        guard !values.isEmpty else { return }
        let avg = values.reduce(0, +) / Double(values.count)

        if avg < target * 0.6 {
            lowFpsTicks += 1
            highFpsTicks = 0
        } else if avg > target * 0.9 {
            highFpsTicks += 1
            lowFpsTicks = 0
        } else {
            lowFpsTicks = 0
            highFpsTicks = 0
        }

        if lowFpsTicks >= 3, streamProfileIndex < Self.streamProfiles.count - 1 {
            streamProfileIndex += 1
            lowFpsTicks = 0
            let p = Self.streamProfiles[streamProfileIndex]
            transportNote = "链路偏慢，直播降到 \(p.width)宽 / \(p.fps)fps"
            restartStreams()
        } else if highFpsTicks >= 15, streamProfileIndex > 0 {
            streamProfileIndex -= 1
            highFpsTicks = 0
            restartStreams()
        }
    }

    private func restartStreams() {
        guard mode == .lan, let status else { return }
        rxCounts.removeAll()
        rxBaseline.removeAll()
        startStreams(with: status)
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
                self.updateRxFps()
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
        // 顺带记住车机上报的所有地址（含 Tailscale 100.x）：
        // 哪怕现在是中继连的，下次切局域网也能直接挑一个能连上的。
        if let info = status.network, let port = info.port {
            for ip in info.ips ?? [] where !knownLANAddresses.contains("\(ip):\(port)") {
                rememberLAN("\(ip):\(port)")
            }
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
