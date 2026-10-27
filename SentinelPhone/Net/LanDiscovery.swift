import Foundation
import Darwin

/// Bonjour 发现：车机端广播 `_carsentinel._tcp`，手机端不用扫描网段。
/// 解析失败时仍会保留 service 名称，用户也可以手动输入 IP。
@MainActor
final class LanDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    var onChange: (([DiscoveredDevice]) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolving: [NetService] = []
    private var found: [String: DiscoveredDevice] = [:]
    private var running = false

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !running else { return }
        running = true
        found.removeAll()
        browser.searchForServices(ofType: "_carsentinel._tcp.", inDomain: "local.")
    }

    func stop() {
        guard running else { return }
        running = false
        browser.stop()
        resolving.forEach { $0.stop() }
        resolving.removeAll()
    }

    func restart() {
        stop()
        start()
    }

    private func publish() {
        let list = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        onChange?(list)
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            service.delegate = self
            self.resolving.append(service)
            service.resolve(withTimeout: 6)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.found.removeValue(forKey: service.name)
            self.publish()
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resolving.removeAll { $0 === sender }
            let host = sender.addresses?.compactMap(Self.ipString(from:)).first
                ?? sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let host, !host.isEmpty else { return }
            let device = DiscoveredDevice(
                id: "\(sender.name)|\(host)",
                name: sender.name,
                host: host,
                port: sender.port > 0 ? sender.port : 8720
            )
            self.found[device.id] = device
            self.publish()
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor [weak self] in
            self?.resolving.removeAll { $0 === sender }
        }
    }

    private static func ipString(from data: Data) -> String? {
        data.withUnsafeBytes { pointer -> String? in
            guard let base = pointer.baseAddress else { return nil }
            let sockaddrPointer = base.assumingMemoryBound(to: sockaddr.self)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(sockaddrPointer.pointee.sa_len)
            let result = getnameinfo(
                sockaddrPointer,
                length,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { return nil }
            return String(cString: host)
        }
    }
}
