import AVFoundation
import Flutter
import UIKit

// MARK: - PiP plugin (iOS 15+)

/// Displays a Picture-in-Picture window over other apps showing the current
/// agent session status and last assistant message.
///
/// Data is fetched from the local HTTP server and kept fresh via SSE.
///
/// Rendering pipeline:
///   UIGraphicsImageRenderer → UIImage → CVPixelBuffer
///   → CMSampleBuffer → AVSampleBufferDisplayLayer → PiP
@available(iOS 15.0, *)
final class FloatingWindowPlugin: NSObject {

    // ── Session state ─────────────────────────────────────────────────────────
    private var serverUri    = ""
    private var sessionId    = ""
    private var workspaceId  = ""
    private var sessionTitle = ""
    private var isDark       = false

    // ── UI state (updated on main thread, triggers re-render) ─────────────────
    private var statusText  = "Loading…"
    private var statusColor = UIColor.systemGreen
    private var messageText = ""

    // ── PiP infrastructure ────────────────────────────────────────────────────
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private weak var hostView: UIView?           // tiny view kept in window tree
    private weak var rootVC: UIViewController?

    // ── Networking ────────────────────────────────────────────────────────────
    private var sseSession: URLSession?
    private var sseTask: URLSessionDataTask?
    private var sseDelegate: SseStreamDelegate?
    private var refreshTimer: Timer?

    // ── Init ──────────────────────────────────────────────────────────────────

    init(rootViewController: UIViewController) {
        rootVC = rootViewController
        super.init()
    }

    func attach(binaryMessenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(
            name: "mobile_agent/floating_window",
            binaryMessenger: binaryMessenger
        )
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    // ── MethodChannel handler ─────────────────────────────────────────────────

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "hasPermission":
            result(AVPictureInPictureController.isPictureInPictureSupported())
        case "openPermissionSettings":
            result(nil)
        case "show":
            let args = call.arguments as? [String: Any] ?? [:]
            show(args: args, result: result)
        case "hide":
            hide()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Show ──────────────────────────────────────────────────────────────────

    private func show(args: [String: Any], result: @escaping FlutterResult) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            result(false)
            return
        }

        serverUri    = args["serverUri"]    as? String ?? ""
        sessionId    = args["sessionId"]    as? String ?? ""
        workspaceId  = args["workspaceId"]  as? String ?? ""
        sessionTitle = args["sessionTitle"] as? String ?? ""
        isDark       = args["darkMode"]     as? Bool   ?? false

        if pipController != nil {
            // Already showing — refresh data with new config
            fetchData()
            result(true)
            return
        }

        // AVAudioSession must be active for PiP to survive app backgrounding.
        configureAudioSession()

        // The display layer must live inside the window hierarchy.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isHidden = true
        rootVC?.view.addSubview(container)
        displayLayer.frame         = container.bounds
        displayLayer.videoGravity  = .resizeAspect
        container.layer.addSublayer(displayLayer)
        hostView = container

        // Enqueue one initial frame before creating the controller (required).
        renderAndEnqueue()

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        pip.delegate = self
        pipController = pip

        // PiP start must be triggered slightly after setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak pip] in
            pip?.startPictureInPicture()
            self?.fetchData()
            self?.startSse()
            // Safety-net poll every 15 s in case SSE misses an event.
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.fetchData()
            }
        }

        result(true)
    }

    // ── Hide ──────────────────────────────────────────────────────────────────

    func hide() {
        pipController?.stopPictureInPicture()
        pipController = nil
        stopSse()
        refreshTimer?.invalidate()
        refreshTimer = nil
        hostView?.removeFromSuperview()
        hostView = nil
    }

    // ── Audio session ─────────────────────────────────────────────────────────

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
        try? session.setActive(true)
    }

    // ── Data fetching ─────────────────────────────────────────────────────────

    private func fetchData() {
        guard !serverUri.isEmpty, !sessionId.isEmpty else { return }
        fetchMessages()
        fetchStatus()
    }

    private func fetchMessages() {
        guard let url = URL(string: "\(serverUri)/session/\(sessionId)/message") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            let text = self.lastAssistantText(from: data)
            DispatchQueue.main.async {
                self.messageText = text ?? "Waiting for messages…"
                self.renderAndEnqueue()
            }
        }.resume()
    }

    private func fetchStatus() {
        guard !workspaceId.isEmpty,
              let url = URL(string: "\(serverUri)/session/status?workspaceId=\(workspaceId)")
        else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let obj  = root[self.sessionId] as? [String: Any] else { return }
            let (text, color) = self.parseStatus(from: obj)
            DispatchQueue.main.async {
                self.statusText  = text
                self.statusColor = color
                self.renderAndEnqueue()
            }
        }.resume()
    }

    // ── SSE ───────────────────────────────────────────────────────────────────

    private func startSse() {
        guard !serverUri.isEmpty,
              let url = URL(string: "\(serverUri)/events") else { return }

        stopSse()

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 0)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache",          forHTTPHeaderField: "Cache-Control")

        let delegate = SseStreamDelegate { [weak self] line in
            self?.handleSseLine(line)
        } onDisconnect: { [weak self] in
            guard let self, self.pipController != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.startSse()
            }
        }
        sseDelegate = delegate
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        sseSession = session
        sseTask = session.dataTask(with: req)
        sseTask?.resume()
    }

    private func stopSse() {
        sseTask?.cancel()
        sseTask     = nil
        sseSession  = nil
        sseDelegate = nil
    }

    private var sseEventType = ""

    private func handleSseLine(_ line: String) {
        if line.hasPrefix("event:") {
            sseEventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            let raw = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let d   = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            let sid = obj["sessionID"] as? String
            switch sseEventType {
            case "session.status":
                if sid == nil || sid == sessionId {
                    let (text, color) = parseStatus(from: obj)
                    DispatchQueue.main.async { [weak self] in
                        self?.statusText  = text
                        self?.statusColor = color
                        self?.renderAndEnqueue()
                    }
                }
            case "message.updated", "message.part.updated", "message.part.delta":
                if sid == nil || sid == sessionId { fetchMessages() }
            default: break
            }
        } else if line.isEmpty {
            sseEventType = ""
        }
    }

    // ── Frame rendering ───────────────────────────────────────────────────────

    /// Renders the current state to a 640×360 image, converts it to a
    /// CVPixelBuffer, wraps it in a CMSampleBuffer, and enqueues it to the
    /// AVSampleBufferDisplayLayer so PiP reflects the latest data.
    private func renderAndEnqueue() {
        let size = CGSize(width: 640, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { [self] ctx in
            let r = ctx.cgContext

            // Background
            let bg = isDark ? UIColor(white: 0.11, alpha: 1) : .white
            bg.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            // Horizontal divider under header
            UIColor(white: isDark ? 0.23 : 0.9, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 58, width: size.width, height: 1))

            // Session title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: isDark ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.11, alpha: 1),
            ]
            sessionTitle.draw(
                in: CGRect(x: 20, y: 14, width: size.width - 40, height: 36),
                withAttributes: titleAttrs
            )

            // Status dot
            r.setFillColor(statusColor.cgColor)
            r.fillEllipse(in: CGRect(x: 20, y: 76, width: 13, height: 13))

            // Status text
            let secondaryColor = isDark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.43, alpha: 1)
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 20),
                .foregroundColor: secondaryColor,
            ]
            statusText.draw(
                in: CGRect(x: 40, y: 70, width: size.width - 60, height: 28),
                withAttributes: statusAttrs
            )

            // Divider under status
            UIColor(white: isDark ? 0.23 : 0.9, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 108, width: size.width, height: 1))

            // Message text (multi-line, truncated at bottom)
            let msgColor = isDark ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.11, alpha: 1)
            let para = NSMutableParagraphStyle()
            para.lineSpacing  = 4
            para.lineBreakMode = .byTruncatingTail
            let msgAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 20),
                .foregroundColor: msgColor,
                .paragraphStyle:  para,
            ]
            let displayMsg = messageText.isEmpty ? "Waiting for messages…" : messageText
            displayMsg.draw(
                in: CGRect(x: 20, y: 118, width: size.width - 40, height: size.height - 138),
                withAttributes: msgAttrs
            )
        }

        guard let pixelBuffer = image.toPixelBuffer(size: size) else { return }

        var timing = CMSampleTimingInfo(
            duration:               CMTime(value: 1, timescale: 30),
            presentationTimeStamp:  CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp:        .invalid
        )
        var fmtDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &fmtDesc
        )
        guard let fmt = fmtDesc else { return }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator:          kCFAllocatorDefault,
            imageBuffer:        pixelBuffer,
            dataReady:          true,
            makeDataReadyCallback: nil,
            refcon:             nil,
            formatDescription:  fmt,
            sampleTiming:       &timing,
            sampleBufferOut:    &sampleBuffer
        )
        guard let sb = sampleBuffer else { return }

        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sb)
    }

    // ── JSON helpers ──────────────────────────────────────────────────────────

    private func parseStatus(from json: [String: Any]) -> (String, UIColor) {
        let phase = json["status"] as? String ?? "idle"
        let msg   = (json["message"] as? String)?.trimmingCharacters(in: .whitespaces)
        switch phase {
        case "busy":       return (msg ?? "Running…",                .systemOrange)
        case "retry":      return (msg.map { "Retry · \($0)" } ?? "Retrying…", .systemOrange)
        case "compacting": return ("Compacting…",                    .systemOrange)
        case "error":      return (msg ?? "Error",                   .systemRed)
        default:           return ("Done",                           .systemGreen)
        }
    }

    private func lastAssistantText(from data: Data) -> String? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        for bundle in arr.reversed() {
            guard let info  = bundle["info"]  as? [String: Any],
                  info["role"] as? String == "assistant",
                  let parts = bundle["parts"] as? [[String: Any]] else { continue }
            let texts = parts.compactMap { part -> String? in
                guard part["type"] as? String == "text",
                      let t = part["text"] as? String else { return nil }
                let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
            let combined = texts.joined(separator: "\n")
            if !combined.isEmpty { return combined }
        }
        return nil
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension FloatingWindowPlugin: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pip: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pip: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pip: AVPictureInPictureController
    ) -> Bool { false }

    func pictureInPictureController(
        _ pip: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pip: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void
    ) { completion() }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 15.0, *)
extension FloatingWindowPlugin: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStopPictureInPicture(
        _ pip: AVPictureInPictureController
    ) {
        // Clean up when the user closes PiP via the system ✕ button.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.stopSse()
            self?.refreshTimer?.invalidate()
            self?.refreshTimer = nil
            self?.hostView?.removeFromSuperview()
            self?.hostView = nil
            self?.pipController = nil
        }
    }
}

// MARK: - SSE stream delegate

private final class SseStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer      = ""
    private let onLine:       (String) -> Void
    private let onDisconnect: () -> Void

    init(onLine: @escaping (String) -> Void, onDisconnect: @escaping () -> Void) {
        self.onLine       = onLine
        self.onDisconnect = onDisconnect
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        buffer += String(data: data, encoding: .utf8) ?? ""
        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            onLine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onDisconnect()
    }
}

// MARK: - UIImage → CVPixelBuffer helper

private extension UIImage {
    /// Renders the image into a fresh ARGB `CVPixelBuffer`.
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        let w = Int(size.width  * scale)
        let h = Int(size.height * scale)
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey:       true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        guard let buf = pb else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(buf),
            width:            w,
            height:           h,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(buf),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedFirst.rawValue
        ), let cg = cgImage else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }
}
