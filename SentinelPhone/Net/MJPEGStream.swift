import Foundation
import UIKit

/// 极简 MJPEG 解析器：把 multipart 流里的 JPEG 逐帧拆出来。
/// 车机端每帧都是完整 JPEG（SOI FFD8 … EOI FFD9），所以不用依赖 boundary。
final class MJPEGStream: NSObject, URLSessionDataDelegate {

    let channelID: String
    private let url: URL
    private let onFrame: (UIImage) -> Void
    private let onError: (String) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var stopped = false
    private var frames = 0

    init(url: URL, channelID: String, onFrame: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void) {
        self.url = url
        self.channelID = channelID
        self.onFrame = onFrame
        self.onError = onError
        super.init()
    }

    func start() {
        guard task == nil else { return }
        stopped = false
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func stop() {
        stopped = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll(keepingCapacity: false)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !stopped else { return }
        buffer.append(data)
        extractFrames()
        if buffer.count > 12 * 1024 * 1024 {
            buffer.removeAll(keepingCapacity: true)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !stopped else { return }
        if let error {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async { [weak self] in
                self?.onError(error.localizedDescription)
            }
        } else if frames == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onError("视频流没有返回画面")
            }
        }
    }

    private func extractFrames() {
        let soi = Data([0xFF, 0xD8])
        let eoi = Data([0xFF, 0xD9])
        var searchStart = buffer.startIndex

        while searchStart < buffer.endIndex,
              let start = buffer.range(of: soi, options: [], in: searchStart..<buffer.endIndex),
              let end = buffer.range(of: eoi, options: [], in: start.upperBound..<buffer.endIndex) {
            let jpeg = buffer.subdata(in: start.lowerBound..<end.upperBound)
            searchStart = end.upperBound
            frames += 1
            if let image = UIImage(data: jpeg) {
                // 在后台线程提前解压成位图，主线程只负责贴上屏幕
                let prepared = image.preparingForDisplay() ?? image
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.onFrame(prepared)
                }
            }
        }

        if searchStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<searchStart)
        }
    }
}
