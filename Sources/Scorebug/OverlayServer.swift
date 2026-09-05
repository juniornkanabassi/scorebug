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
        let server = HTTPServer(address: .loopback(port: port))
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

        let handler = StateSocketHandler(broadcaster: broadcaster) { [weak self] in
            String(decoding: await self?.stateJSON() ?? Data("{}".utf8), as: UTF8.self)
        }
        await server.appendRoute("GET /ws", to: .webSocket(handler))

        task = Task { try? await server.run() }
        try await server.waitUntilListening(timeout: 5)
    }

    func stop() async { await server?.stop(); task?.cancel() }
}
