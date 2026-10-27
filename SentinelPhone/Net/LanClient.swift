import Foundation
import UIKit

/// 局域网 HTTP 客户端。车机端提供 REST + MJPEG，地址类似 http://192.168.1.23:8720。
final class LanClient {

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    convenience init?(rawAddress: String) {
        guard let url = Self.normalize(rawAddress) else { return nil }
        self.init(baseURL: url)
    }

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    func endpoint(_ path: String) -> URL? {
        if let url = URL(string: path, relativeTo: baseURL) {
            return url.absoluteURL
        }
        return nil
    }

    func streamURL(channelID: String) -> URL? {
        endpoint("/api/v1/stream/\(channelID).mjpeg")
    }

    func snapshotURL(channelID: String) -> URL? {
        endpoint("/api/v1/snapshot/\(channelID).jpg?ts=\(Int(Date().timeIntervalSince1970))")
    }

    // MARK: - REST

    func status() async throws -> SentinelStatus {
        try await getJSON("/api/v1/status")
    }

    func channels() async throws -> [SentinelChannel] {
        struct Response: Decodable { var channels: [SentinelChannel]? }
        let response: Response = try await getJSON("/api/v1/channels")
        return response.channels ?? []
    }

    func sessions() async throws -> [RecordingSession] {
        struct Response: Decodable { var sessions: [RecordingSession]? }
        let response: Response = try await getJSON("/api/v1/sessions")
        return response.sessions ?? []
    }

    func events() async throws -> [SentinelEvent] {
        struct Response: Decodable { var events: [SentinelEvent]? }
        let response: Response = try await getJSON("/api/v1/events")
        return response.events ?? []
    }

    func config() async throws -> SentinelConfigSnapshot {
        struct Response: Decodable {
            var config: SentinelConfigSnapshot?
            var ok: Bool?
        }
        let response: Response = try await getJSON("/api/v1/config")
        guard let config = response.config else { throw SentinelAPIError.empty }
        return config
    }

    @discardableResult
    func sendControl(_ action: String, payload: [String: Any] = [:]) async throws -> Data {
        var body: [String: Any] = ["action": action]
        for (key, value) in payload { body[key] = value }
        return try await postJSON("/api/v1/control", body: body)
    }

    // MARK: - 图片

    func imageData(path: String) async throws -> Data {
        guard let url = endpoint(path) else { throw SentinelAPIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard !data.isEmpty else { throw SentinelAPIError.empty }
        return data
    }

    func image(path: String) async throws -> UIImage {
        let data = try await imageData(path: path)
        guard let image = UIImage(data: data) else { throw SentinelAPIError.decode("图片格式错误") }
        return image
    }

    // MARK: - 内部

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        guard let url = endpoint(path) else { throw SentinelAPIError.badURL }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        return try decode(data)
    }

    private func postJSON(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = endpoint(path) else { throw SentinelAPIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SentinelAPIError.decode(error.localizedDescription)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw SentinelAPIError.http(http.statusCode)
        }
    }
}

enum SentinelAPIError: LocalizedError {
    case badURL
    case empty
    case http(Int)
    case decode(String)
    case timeout
    case offline

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址格式不正确"
        case .empty: return "设备返回了空数据"
        case .http(let code): return "设备返回 HTTP \(code)"
        case .decode(let message): return "数据解析失败：\(message)"
        case .timeout: return "连接超时"
        case .offline: return "连接已断开"
        }
    }
}
