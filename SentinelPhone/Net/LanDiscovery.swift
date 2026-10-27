import Foundation
import Darwin

/// Bonjour + UDP 双通道发现。
///
/// 有些车机 / 路由器会把 mDNS 多播屏蔽，但 UDP 广播还能通；
/// 所以这里两条路一起走，任一条发现都会出现在「设备」页。
@MainActor
final class LanDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    var onChange: (([DiscoveredDevice]) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolving: [NetService] = []
    private var found: [String: DiscoveredDevice] = [:]
    private var running = false

    private var udpSocket: Int32?
    private var udpTimer: DispatchSourceTimer?
    private let udpQueue = DispatchQueue(label: "carsentinel.lan-discovery.udp")

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !running else { return }
        running = true
        found.removeAll()
        browser.searchForServices(ofType: "_carsentinel._tcp.", inDomain: "local.")
        startUDP()
    }

    func stop() {
        guard running else { return }
        running = false
        browser.stop()
        resolving.forEach { $0.stop() }
        resolving.removeAll()
        stopUDP()
    }

    func restart() {
        stop()
        start()
    }

    private func publish() {
        let list = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        onChange?(list)
    }

    // MARK: - Bonjour

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
            // 只取 IPv4：Android NSD 常把 IPv6 link-local 放在前面，URLSession 用不了
            guard Int(sockaddrPointer.pointee.sa_family) == AF_INET else { return nil }
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

    // MARK: - UDP 广播兜底

    private func startUDP() {
        stopUDP()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }

        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(8721).bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return
        }

        udpSocket = fd
        let timer = DispatchSource.makeTimerSource(queue: udpQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 2.0)
        timer.setEventHandler {
            Self.sendProbe(fd: fd)
        }
        timer.resume()
        udpTimer = timer

        udpQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 2048)
            while true {
                var sender = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let read = withUnsafeMutablePointer(to: &sender) { pointer -> Int in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &length)
                    }
                }
                if read <= 0 { break }
                let data = Data(buffer[0..<read])
                Task { @MainActor in
                    self?.handleUDP(data)
                }
            }
        }
    }

    private func stopUDP() {
        udpTimer?.cancel()
        udpTimer = nil
        if let fd = udpSocket {
            close(fd)
            udpSocket = nil
        }
    }

    private nonisolated static func sendProbe(fd: Int32) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(8721).bigEndian
        address.sin_addr.s_addr = inet_addr("255.255.255.255")

        let bytes = [UInt8]("SENTINEL_DISCOVER".utf8)
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, base, bytes.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func handleUDP(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard (object["type"] as? String) == "car_sentinel" else { return }
        guard let host = object["ip"] as? String, !host.isEmpty,
              let port = object["port"] as? Int, port > 0 else { return }
        let id = object["id"] as? String ?? host
        let name = object["name"] as? String ?? "车载哨兵"
        let device = DiscoveredDevice(
            id: "\(id)|\(host)",
            name: name,
            host: host,
            port: port
        )
        found[device.id] = device
        publish()
    }
}
