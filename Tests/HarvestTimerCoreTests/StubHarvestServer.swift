import Foundation

@testable import HarvestTimerCore

/// One canned reply, and the request that drew it out.
struct StubExchange {
    var request: URLRequest
    var body: Data?
}

/// A stand-in for api.harvestapp.com. Hand it the replies you want, in order,
/// then read back the requests that were made to get them.
///
/// A `URLProtocol` rather than a fake `URLSession`, so the real request goes
/// through URL loading and the headers, query, and body under test are the
/// ones that would go on the wire.
final class StubHarvestServer: @unchecked Sendable {
    /// What to answer with. Each call takes the next one; the last is reused
    /// if more calls come, so a test needing one answer supplies one.
    enum Reply {
        case json(String, status: Int = 200)
        case status(Int, body: String = "")
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var replies: [Reply] = []
    private var exchanges: [StubExchange] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    convenience init(json: String) {
        self.init([.json(json)])
    }

    /// Every request made, in order.
    var requests: [StubExchange] {
        lock.withLock { exchanges }
    }

    var callCount: Int { requests.count }

    /// A session that reaches this stub and nothing else.
    ///
    /// The marker header goes on before the session is made, because a session
    /// copies its configuration at birth and ignores later edits.
    func session() -> URLSession {
        let key = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [StubURLProtocol.sessionHeader: key]
        StubURLProtocol.register(self, forKey: key)
        return URLSession(configuration: configuration)
    }

    func api(token: String = "token", accountId: String = "123") -> HarvestAPI {
        HarvestAPI(
            credentials: Keychain.Credentials(token: token, accountId: accountId),
            session: session()
        )
    }

    fileprivate func next(for request: URLRequest, body: Data?) -> Reply {
        lock.withLock {
            exchanges.append(StubExchange(request: request, body: body))
            guard !replies.isEmpty else { return .status(500, body: "no reply set up") }
            return replies.count == 1 ? replies[0] : replies.removeFirst()
        }
    }
}

/// Routes a session's requests to the stub registered for it. Keyed by the
/// session's identifier so suites running side by side do not cross.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubHarvestServer] = [:]

    static func register(_ server: StubHarvestServer, forKey key: String) {
        lock.withLock { servers[key] = server }
    }

    private static func server(for request: URLRequest) -> StubHarvestServer? {
        lock.withLock { servers[request.value(forHTTPHeaderField: sessionHeader) ?? ""] }
    }

    static let sessionHeader = "X-Stub-Session"

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol strips the body off the request it is handed, so read it
        // back from the stream the loader kept.
        let body = request.httpBody ?? request.httpBodyStream.map(Data.init(reading:))
        guard let server = Self.server(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        switch server.next(for: request, body: body) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let text, let status):
            reply(status: status, data: Data(text.utf8))
        case .status(let status, let text):
            reply(status: status, data: Data(text.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func reply(status: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
    }
}

private extension Data {
    init(reading stream: InputStream) {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        self = data
    }
}

extension StubExchange {
    var path: String { request.url?.path ?? "" }

    var method: String { request.httpMethod ?? "" }

    func header(_ name: String) -> String? {
        request.value(forHTTPHeaderField: name)
    }

    /// The query as a dictionary, since its order is not fixed.
    var query: [String: String] {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { first, _ in first }
    }

    /// The body read back as JSON, for checking what was sent.
    var json: [String: Any] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) else { return [:] }
        return object as? [String: Any] ?? [:]
    }
}
