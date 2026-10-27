import Foundation
import UIKit
import Combine

/// 远程中继 WebSocket 客户端。
///
/// 文本帧：hello / status / cmd / req / res
/// 二进制帧：4 字节大端 header 长度 + JSON header + JPEG
/// header = {"kind":"frame","ch":"front","w":960,"h":540,"ts":...}
@MainActor
final class RelayClient: NSObject, URLSessionWebSocketDelegate {

    var onState: ((Bool, String?) -> Void)?
    var onStatus: ((SentinelStatus) -> Void)?
    var onFrame: ((String, UIImage) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pendingJSON: [String: CheckedContinuation<Data, Error>] = [:]
    private var pendingImage: [String: CheckedContinuation<UIImage, Error>] = [:]
    private var pendingData: [String: CheckedContinuation<Data, Error>] = [:]
    private var shouldReconnect = false
    private var reconnectTask: Task<Void, Never>?
    private var lastURL: URL?
    private var generation = 0
    private var receiveLoopGeneration = -1
    private var livePending: [String: Data] = [:]
    private var liveDecoding: Set<String> = []

    var isConnected: Bool {
        task?.state == .running
    }

    func connect(base: String, key: String, deviceID: String) throws {
        guard let url = Self.websocketURL(base: base, key: key, deviceID: deviceID) else {
            throw SentinelAPIError.badURL
        }
        shouldReconnect = true
        lastURL = url
        open(url: url)
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeSocket()
        failAll(SentinelAPIError.offline)
        onState?(false, nil)
    }

    // MARK: - 请求

    func requestJSONData(path: String) async throws -> Data {
        guard isConnected else { throw SentinelAPIError.offline }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingJSON[id] = continuation
            sendText(["type": "req", "id": id, "path": path])
            scheduleJSONTimeout(id)
        }
    }

    func requestImage(path: String) async throws -> UIImage {
        guard isConnected else { throw SentinelAPIError.offline }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            pendingImage[id] = continuation
            sendText(["type": "img", "id": id, "path": path])
            scheduleImageTimeout(id)
        }
    }

    /// 请求任意二进制数据，例如录像 zip 导出包。
    func requestData(path: String) async throws -> Data {
        guard isConnected else { throw SentinelAPIError.offline }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingData[id] = continuation
            sendText(["type": "img", "id": id, "path": path])
            scheduleDataTimeout(id)
        }
    }

    func requestFrame(sessionID: String, index: Int) async throws -> UIImage {
        guard isConnected else { throw SentinelAPIError.offline }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            pendingImage[id] = continuation
            sendText(["type": "frame", "id": id, "sessionId": sessionID, "index": index])
            scheduleImageTimeout(id)
        }
    }

    func sendCommand(_ action: String, payload: [String: Any] = [:]) {
        sendText(["type": "cmd", "action": action, "payload": payload])
    }

    func refreshStatus() {
        Task { @MainActor in
            guard let data = try? await requestJSONData(path: "/api/v1/status") else { return }
            if let status = try? JSONDecoder().decode(SentinelStatus.self, from: data) {
                self.onStatus?(status)
            }
        }
    }

    // MARK: - 连接

    private func open(url: URL) {
        closeSocket()
        generation += 1
        let current = generation
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        onState?(false, "正在连接中继…")
        task.resume()
        receiveNext(generation: current)
    }

    private func closeSocket() {
        receiveLoopGeneration = -1
        livePending.removeAll()
        liveDecoding.removeAll()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveNext(generation current: Int) {
        guard current == generation, let task else { return }
        receiveLoopGeneration = current
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveNext(generation: current)
                case .failure(let error):
                    self.handleFailure(error)
                }
            }
        }
    }

    private func handleOpen() {
        onState?(true, nil)
        sendText(["type": "hello", "role": "viewer"])
        refreshStatus()
    }

    private func handleFailure(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        closeSocket()
        failAll(error)
        onState?(false, error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, let lastURL else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled, self.shouldReconnect else { return }
            self.open(url: lastURL)
        }
    }

    // MARK: - 收消息

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleText(text)
        case .data(let data):
            handleBinary(data)
        @unknown default:
            break
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = object["type"] as? String ?? ""

        if type == "status" || type == "hello" {
            if let statusObject = object["status"],
               let statusData = try? JSONSerialization.data(withJSONObject: statusObject),
               let status = try? JSONDecoder().decode(SentinelStatus.self, from: statusData) {
                onStatus?(status)
            }
            return
        }

        if type == "res" {
            let id = object["id"] as? String ?? ""
            let ok = object["ok"] as? Bool ?? false
            if ok {
                if let body = object["body"],
                   let bodyData = try? JSONSerialization.data(withJSONObject: body),
                   let continuation = pendingJSON.removeValue(forKey: id) {
                    continuation.resume(returning: bodyData)
                    return
                }
                if let continuation = pendingJSON.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.empty)
                    return
                }
                if let continuation = pendingImage.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.empty)
                }
                if let continuation = pendingData.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.empty)
                }
            } else {
                let message = object["error"] as? String ?? "中继请求失败"
                if let continuation = pendingJSON.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.decode(message))
                }
                if let continuation = pendingImage.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.decode(message))
                }
                if let continuation = pendingData.removeValue(forKey: id) {
                    continuation.resume(throwing: SentinelAPIError.decode(message))
                }
            }
        }
    }

    private func handleBinary(_ data: Data) {
        guard data.count > 4 else { return }
        let prefix = [UInt8](data.prefix(4))
        let headerLength = (Int(prefix[0]) << 24) | (Int(prefix[1]) << 16) | (Int(prefix[2]) << 8) | Int(prefix[3])
        guard headerLength > 0, data.count >= 4 + headerLength else { return }
        let headerData = data.subdata(in: 4..<(4 + headerLength))
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { return }
        let payload = data.subdata(in: (4 + headerLength)..<data.count)
        let id = header["id"] as? String

        // 先处理数据请求（例如录像 zip）：不要求能解码成图片
        if let id, let continuation = pendingData.removeValue(forKey: id) {
            continuation.resume(returning: payload)
            return
        }

        let kind = header["kind"] as? String ?? ""

        // 直播帧：解码放到后台线程，并且同一机位只解最新一帧，避免积压和主线程卡顿
        if kind == "frame", id == nil, let channel = header["ch"] as? String {
            enqueueLiveFrame(channel: channel, payload: payload)
            return
        }

        guard let image = Self.preparedImage(payload) else {
            if let id, let continuation = pendingImage.removeValue(forKey: id) {
                continuation.resume(throwing: SentinelAPIError.decode("画面解码失败"))
            }
            return
        }

        if let id, let continuation = pendingImage.removeValue(forKey: id) {
            continuation.resume(returning: image)
        }
    }

    // MARK: - 直播帧解码

    /// 每个机位最多同时解码一帧；新帧覆盖旧帧，始终显示最新画面。
    private func enqueueLiveFrame(channel: String, payload: Data) {
        livePending[channel] = payload
        guard !liveDecoding.contains(channel) else { return }
        liveDecoding.insert(channel)
        decodeNextLive(channel)
    }

    private func decodeNextLive(_ channel: String) {
        guard let payload = livePending.removeValue(forKey: channel) else {
            liveDecoding.remove(channel)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let image = Self.preparedImage(payload)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let image { self.onFrame?(channel, image) }
                self.decodeNextLive(channel)
            }
        }
    }

    /// 后台提前解压成位图，SwiftUI 渲染时不再占用主线程。
    nonisolated static func preparedImage(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        if let prepared = image.preparingForDisplay() { return prepared }
        return image
    }

    // MARK: - 发送

    private func sendText(_ object: [String: Any]) {
        guard let task, task.state == .running,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.failAll(error)
            }
        }
    }

    private func failAll(_ error: Error) {
        let json = pendingJSON
        pendingJSON.removeAll()
        json.values.forEach { $0.resume(throwing: error) }
        let images = pendingImage
        pendingImage.removeAll()
        images.values.forEach { $0.resume(throwing: error) }
        let dataRequests = pendingData
        pendingData.removeAll()
        dataRequests.values.forEach { $0.resume(throwing: error) }
    }

    private func scheduleJSONTimeout(_ id: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, let continuation = self.pendingJSON.removeValue(forKey: id) else { return }
            continuation.resume(throwing: SentinelAPIError.timeout)
        }
    }

    private func scheduleImageTimeout(_ id: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, let continuation = self.pendingImage.removeValue(forKey: id) else { return }
            continuation.resume(throwing: SentinelAPIError.timeout)
        }
    }

    private func scheduleDataTimeout(_ id: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, let continuation = self.pendingData.removeValue(forKey: id) else { return }
            continuation.resume(throwing: SentinelAPIError.timeout)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor [weak self] in self?.handleOpen() }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.closeSocket()
            self.failAll(SentinelAPIError.offline)
            self.onState?(false, "中继连接已关闭")
            self.scheduleReconnect()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.handleFailure(error)
        }
    }

    // MARK: - 地址

    static func websocketURL(base: String, key: String, deviceID: String) -> URL? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("https://") {
            text = "wss://" + text.dropFirst("https://".count)
        } else if text.hasPrefix("http://") {
            text = "ws://" + text.dropFirst("http://".count)
        } else if !text.hasPrefix("wss://") && !text.hasPrefix("ws://") {
            text = "wss://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else {
            return nil
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/ws"
        }
        var items = components.queryItems ?? []
        items.removeAll { ["role", "device", "key"].contains($0.name) }
        items.append(URLQueryItem(name: "role", value: "viewer"))
        items.append(URLQueryItem(name: "device", value: deviceID))
        if !key.isEmpty { items.append(URLQueryItem(name: "key", value: key)) }
        components.queryItems = items
        return components.url
    }
}

/// 中继的设备目录（HTTP GET /devices?key=...），用于手机端选择车机。
enum RelayDirectory {

    static func fetchDevices(base: String, key: String) async throws -> [RelayDevice] {
        guard var text = Optional(base.trimmingCharacters(in: .whitespacesAndNewlines)), !text.isEmpty else {
            throw SentinelAPIError.badURL
        }
        if text.hasPrefix("wss://") {
            text = "https://" + text.dropFirst("wss://".count)
        } else if text.hasPrefix("ws://") {
            text = "http://" + text.dropFirst("ws://".count)
        } else if !text.hasPrefix("https://") && !text.hasPrefix("http://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else {
            throw SentinelAPIError.badURL
        }
        components.path = "/devices"
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { throw SentinelAPIError.badURL }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SentinelAPIError.http(http.statusCode)
        }
        struct Response: Decodable {
            var devices: [RelayDevice]?
            var ok: Bool?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.devices ?? []
    }
}
