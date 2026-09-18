import Foundation

enum AlmanacAPIError: LocalizedError {
    case unauthorized
    case personNotFound
    case http(Int, String)
    case network(Error)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Almanac didn't accept that API key — issue a fresh one from Almanac's /api_keys page."
        case .personNotFound:
            return "No Almanac person matches that email."
        case .http(let code, let body):
            return "Almanac returned \(code): \(body)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .malformed(let detail):
            return "Couldn't read Almanac's answer: \(detail)"
        }
    }
}

public struct AlmanacAPI: AlmanacClient {
    let credentials: AlmanacCredentials
    /// The shared session in the app. Tests hand in one backed by a stub, so
    /// they can check what goes out and choose what comes back.
    let session: URLSession

    public init(credentials: AlmanacCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Not private, so tests read JSON with the decoder the app ships rather
    /// than one of their own. GraphQL's own fields already arrive camelCase,
    /// so this only has work to do on the REST endpoint's snake_case.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public func people() async throws -> [AlmanacPerson] {
        struct Response: Decodable { let people: [AlmanacPerson] }
        let response: Response = try await graphQL(query: "{ people { id email } }")
        return response.people
    }

    /// The current quarter's total pace for one person. Deliberately asked
    /// for by id rather than folded into `people()`, which would have
    /// Almanac compute every employee's pace just to read one.
    public func totalPace(personId: String) async throws -> AlmanacPace {
        struct PersonResponse: Decodable { let totalPace: AlmanacPace }
        struct Response: Decodable { let person: PersonResponse? }
        let query = """
        { person(id: "\(personId)") { totalPace { \
        suggestedDailyPace target worked remaining daysIntoReport } } }
        """
        let response: Response = try await graphQL(query: query)
        guard let person = response.person else { throw AlmanacAPIError.personNotFound }
        return person.totalPace
    }

    public func constraints(email: String) async throws -> [AlmanacConstraint] {
        try await get("api/constraints/next_constraints", query: ["email": email])
    }

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    private func graphQL<T: Decodable>(query: String) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        let data = try await rawRequest("graphql", method: "POST", query: [:], body: body)
        do {
            return try Self.decoder.decode(Envelope<T>.self, from: data).data
        } catch {
            throw AlmanacAPIError.malformed(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        let data = try await rawRequest(path, method: "GET", query: query, body: nil)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw AlmanacAPIError.malformed(error.localizedDescription)
        }
    }

    private func rawRequest(
        _ path: String,
        method: String,
        query: [String: String],
        body: Data?
    ) async throws -> Data {
        guard let base = URL(string: credentials.baseURL) else {
            throw AlmanacAPIError.malformed("not a URL: \(credentials.baseURL)")
        }
        var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AlmanacAPIError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299:
            return data
        case 401:
            throw AlmanacAPIError.unauthorized
        default:
            throw AlmanacAPIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
