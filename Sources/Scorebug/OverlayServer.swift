// FlyingFox on 127.0.0.1:<port>. Static overlays, /overlay/{h|v}/{slot}, /api/state, POST /api/match/{slot}/command, /crests, /ws.
import Foundation
import FlyingFox
import ScorebugCore

actor Broadcaster {
    private var clients: [UUID: AsyncStream<WSMessage>.Continuation] = [:]
    var count: Int { clients.count }

    func register(_ continuation: AsyncStream<WSMessage>.Continuation) -> UUID {
        let id = UUID(); clients[id] = continuation; return id
    }
    func unregister(_ id: UUID) { clients[id]?.finish(); clients[id] = nil }
    func broadcast(_ text: String) { for c in clients.values { c.yield(.text(text)) } }
}

struct StateSocketHandler: WSMessageHandler {
    let broadcaster: Broadcaster
    let initial: @Sendable () async -> String

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let (stream, continuation) = AsyncStream<WSMessage>.makeStream()
        let id = await broadcaster.register(continuation)
        continuation.yield(.text(await initial()))
        Task {
            for await message in client {
                if case .text(let t) = message, t == "state" { continuation.yield(.text(await initial())) }
            }
            await broadcaster.unregister(id)
        }
        return stream
    }
}

final class OverlayServer: @unchecked Sendable {
    let port: UInt16
    let resolver: OverlayResolver
    let crestsDirectory: URL
    private weak var model: AppModel?
    private let broadcaster = Broadcaster()
    private var server: HTTPServer?
    private var task: Task<Void, Never>?

    init(port: UInt16, resolver: OverlayResolver, crestsDirectory: URL, model: AppModel) {
        self.port = port; self.resolver = resolver; self.crestsDirectory = crestsDirectory; self.model = model
    }

    func broadcast(_ data: Data) async {
        await broadcaster.broadcast(String(decoding: data, as: UTF8.self))
    }

    private func stateJSON() async -> Data {
        guard let model else { return Data("{}".utf8) }
        return await MainActor.run { model.snapshotData() }
    }

    func start() async throws {
        // IPv4 loopback on purpose: .loopback picks ::1 on macOS, which refuses 127.0.0.1 clients (curl, scripts, the Stream Deck plugin). "localhost" clients fall back to 127.0.0.1 themselves.
        let server = HTTPServer(address: try .inet(ip4: "127.0.0.1", port: port))
        self.server = server
        let resolver = self.resolver
        let crests = self.crestsDirectory

        await server.appendRoute("GET /", handler: { [weak self] _ in
            let base = "http://localhost:\(self?.port ?? 8600)"
            let html = """
            <!doctype html><meta charset=utf-8><title>Scorebug</title>
            <body style="font-family:-apple-system,Helvetica;padding:32px;background:#111;color:#eee">
            <h1>Scorebug is running</h1><p>Add these as OBS browser sources at position 0,0 with no crop or scale.</p>
            <ul><li>\(base)/overlay/h/1 at 1920x1080</li><li>\(base)/overlay/h/2 at 1920x1080</li>
            <li>\(base)/overlay/v/1 at 1080x1920 on the vertical canvas</li><li>\(base)/overlay/v/2 at 1080x1920 on the vertical canvas</li></ul>
            """
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "text/html; charset=utf-8"], body: Data(html.utf8))
        })

        await server.appendRoute("GET /overlay/:orientation/:slot", handler: { request in
            let o: String? = request.routeParameters["orientation"]
            let s: String? = request.routeParameters["slot"]
            guard let o, ["h", "v"].contains(o), let s, ["1", "2"].contains(s),
                  let file = resolver.file(for: "shell.html"), let shell = try? String(contentsOf: file, encoding: .utf8) else {
                return HTTPResponse(statusCode: .notFound)
            }
            let html = shell.replacingOccurrences(of: "{{ORIENTATION}}", with: o).replacingOccurrences(of: "{{SLOT}}", with: s)
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-store"], body: Data(html.utf8))
        })

        let serve: @Sendable (URL?) -> HTTPResponse = { url in
            guard let url, let data = try? Data(contentsOf: url) else { return HTTPResponse(statusCode: .notFound) }
            return HTTPResponse(statusCode: .ok, headers: [.contentType: MIME.type(for: url), .cacheControl: "no-cache"], body: data)
        }
        await server.appendRoute("GET /assets/*", handler: { request in
            serve(resolver.file(for: String(request.path.dropFirst("/assets/".count))))
        })
        await server.appendRoute("GET /themes/*", handler: { request in
            serve(resolver.file(for: "themes/" + String(request.path.dropFirst("/themes/".count))))
        })
        await server.appendRoute("GET /crests/*", handler: { request in
            let name = String(request.path.dropFirst("/crests/".count)).removingPercentEncoding ?? ""
            guard !name.contains("/"), !name.contains("..") else { return HTTPResponse(statusCode: .notFound) }
            return serve(crests.appendingPathComponent(name))
        })

        await server.appendRoute("GET /preview/backdrop", handler: { [weak self] request in
            guard let model = self?.model else { return HTTPResponse(statusCode: .serviceUnavailable) }
            let path = await MainActor.run { model.settings.previewBackdrop }
            guard let path, path != "pitch", let data = FileManager.default.contents(atPath: path) else {
                return HTTPResponse(statusCode: .notFound)
            }
            let mime = backdropMIME(for: path)
            // A single byte range is enough for WebKit's <video> to seek and buffer a local muted loop.
            if let rangeHeader = request.headers[.range], let range = singleByteRange(rangeHeader, count: data.count) {
                return HTTPResponse(statusCode: .partialContent, headers: [
                    .contentType: mime, .acceptRanges: "bytes",
                    .contentRange: "bytes \(range.lowerBound)-\(range.upperBound)/\(data.count)",
                ], body: Data(data[range]))
            }
            return HTTPResponse(statusCode: .ok, headers: [.contentType: mime, .acceptRanges: "bytes", .cacheControl: "no-store"], body: data)
        })

        await server.appendRoute("GET /api/state", handler: { [weak self] _ in
            let data = await self?.stateJSON() ?? Data("{}".utf8)
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json; charset=utf-8", .cacheControl: "no-store"], body: data)
        })
        await server.appendRoute("GET /api/library", handler: { [weak self] _ in
            guard let model = self?.model else { return HTTPResponse(statusCode: .serviceUnavailable) }
            let data = await MainActor.run { (try? JSONCoding.encoder().encode(model.library)) ?? Data() }
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json; charset=utf-8"], body: data)
        })
        await server.appendRoute("POST /api/match/:slot/command", handler: { [weak self] request in
            guard let model = self?.model else { return HTTPResponse(statusCode: .serviceUnavailable) }
            let slotText: String? = request.routeParameters["slot"]
            guard let slot = slotText.flatMap(Int.init), [1, 2].contains(slot) else {
                return HTTPResponse(statusCode: .badRequest, body: Data("slot must be 1 or 2".utf8))
            }
            let body = try await request.bodyData
            let req: CommandRequest
            do { req = try JSONCoding.decoder().decode(CommandRequest.self, from: body) }
            catch { return HTTPResponse(statusCode: .badRequest, body: Data("invalid command JSON: \(error)".utf8)) }
            let result: Result<Data, Error> = await MainActor.run {
                do { try model.applyRequest(req, slot: slot); return .success(model.snapshotData()) } catch { return .failure(error) }
            }
            switch result {
            case .success(let data): return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json; charset=utf-8"], body: data)
            case .failure(let error): return HTTPResponse(statusCode: .badRequest, body: Data("\(error)".utf8))
            }
        })

        // SCOREBUG_TEST_KEYS=1 only: synthesises a key event into the key window, so a capture script can drive
        // the app (menu shortcuts, text fields) without real mouse or keyboard input. See rule 16.
        await server.appendRoute("POST /api/test/key", handler: { request in
            guard ProcessInfo.processInfo.environment["SCOREBUG_TEST_KEYS"] != nil else { return HTTPResponse(statusCode: .notFound) }
            guard let req = try? JSONCoding.decoder().decode(TestKeyRequest.self, from: try await request.bodyData) else {
                return HTTPResponse(statusCode: .badRequest, body: Data("invalid key JSON".utf8))
            }
            let sent = await MainActor.run { AppModel.sendTestKey(req) }
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json; charset=utf-8"], body: Data(#"{"sent":\#(sent)}"#.utf8))
        })

        let handler = StateSocketHandler(broadcaster: broadcaster) { [weak self] in
            String(decoding: await self?.stateJSON() ?? Data("{}".utf8), as: UTF8.self)
        }
        await server.appendRoute("GET /ws", to: .webSocket(handler))

        task = Task { try? await server.run() }
        try await server.waitUntilListening(timeout: 5)
    }

    func stop() async { await server?.stop(); task?.cancel() }
}

/// Body of POST /api/test/key: `{"keyCode":125,"characters":"","modifiers":[]}`. Modifier names match
/// NSEvent.ModifierFlags: shift, command, option, control.
struct TestKeyRequest: Decodable, Sendable {
    var keyCode: UInt16
    var characters: String?
    var modifiers: [String]?
}

/// MIME for a preview backdrop file. Not the shared `MIME.type(for:)` (owned by another file): that one has
/// no video cases, since nothing else served here is ever a video.
private func backdropMIME(for path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "mp4", "m4v": return "video/mp4"
    case "mov": return "video/quicktime"
    case "webm": return "video/webm"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "heic": return "image/heic"
    default: return "application/octet-stream"
    }
}

/// Parses a single `Range: bytes=<start>-<end>` header (the only form WebKit sends for a local file), clamped
/// to the data's bounds. Multi-range and suffix ("-500") forms are not needed for a short local loop; either
/// falls back to serving the whole file (returning nil here).
private func singleByteRange(_ header: String, count: Int) -> ClosedRange<Int>? {
    guard header.hasPrefix("bytes="), !header.contains(",") else { return nil }
    let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, let start = Int(parts[0]) else { return nil }
    let end = Int(parts[1]).map { min($0, count - 1) } ?? count - 1
    guard start <= end, start < count else { return nil }
    return start...end
}
