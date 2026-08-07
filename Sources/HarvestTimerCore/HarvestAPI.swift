import Foundation

enum HarvestAPIError: LocalizedError {
    case unauthorized
    case accountMismatch
    case http(Int, String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Token not accepted — re-copy it from id.getharvest.com/developers."
        case .accountMismatch:
            return "Account ID doesn't match this token. Use the numeric ID shown next to the token."
        case .http(let code, let body):
            return "Harvest returned \(code): \(body)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

public struct HarvestAPI: HarvestClient {
    let credentials: Keychain.Credentials
    /// The shared session in the app. Tests hand in one backed by a stub, so
    /// they can check what goes out and choose what comes back.
    let session: URLSession

    init(credentials: Keychain.Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    static let baseURL = URL(string: "https://api.harvestapp.com/v2")!

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// The one decoder Harvest's replies go through. Not private, so tests
    /// read JSON with the decoder the app ships rather than one of their own.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unparseable date: \(string)"
                ))
            }
            return date
        }
        return decoder
    }()

    public func currentUser() async throws -> HarvestUser {
        try await get("users/me")
    }

    public func company() async throws -> HarvestCompany {
        try await get("company")
    }

    public func timeEntries(from: Day, to: Day, userId: Int64) async throws -> [TimeEntry] {
        var entries: [TimeEntry] = []
        var page = 1
        while true {
            let result: TimeEntriesPage = try await get(
                "time_entries",
                query: [
                    "from": from.name,
                    "to": to.name,
                    "user_id": String(userId),
                    "page": String(page),
                    "per_page": "100",
                ]
            )
            entries.append(contentsOf: result.timeEntries)
            guard let next = result.nextPage else { break }
            page = next
        }
        return entries
    }

    public func projectAssignments() async throws -> [ProjectAssignment] {
        var assignments: [ProjectAssignment] = []
        var page = 1
        while true {
            let result: ProjectAssignmentsPage = try await get(
                "users/me/project_assignments",
                query: ["page": String(page), "per_page": "100"]
            )
            assignments.append(contentsOf: result.projectAssignments)
            guard let next = result.nextPage else { break }
            page = next
        }
        return assignments
    }

    public func startTimer(projectId: Int64, taskId: Int64, spentDate: Day) async throws -> TimeEntry {
        // No hours, so Harvest starts it running.
        try await send("time_entries", method: "POST", body: EntryFields(
            projectId: projectId,
            taskId: taskId,
            spentDate: spentDate
        ))
    }

    public func createEntry(
        projectId: Int64,
        taskId: Int64,
        spentDate: Day,
        hours: Double,
        notes: String?
    ) async throws -> TimeEntry {
        try await send("time_entries", method: "POST", body: EntryFields(
            projectId: projectId,
            taskId: taskId,
            spentDate: spentDate,
            hours: hours,
            notes: notes.flatMap { $0.isEmpty ? nil : $0 }
        ))
    }

    public func restart(entryId: Int64) async throws -> TimeEntry {
        try await send("time_entries/\(entryId)/restart", method: "PATCH")
    }

    public func stop(entryId: Int64) async throws -> TimeEntry {
        try await send("time_entries/\(entryId)/stop", method: "PATCH")
    }

    public func updateHours(entryId: Int64, hours: Double) async throws -> TimeEntry {
        try await send("time_entries/\(entryId)", method: "PATCH", body: EntryFields(hours: hours))
    }

    public func updateProjectTask(entryId: Int64, projectId: Int64, taskId: Int64) async throws -> TimeEntry {
        try await send("time_entries/\(entryId)", method: "PATCH", body: EntryFields(
            projectId: projectId,
            taskId: taskId
        ))
    }

    public func updateNotes(entryId: Int64, notes: String) async throws -> TimeEntry {
        try await send("time_entries/\(entryId)", method: "PATCH", body: EntryFields(notes: notes))
    }

    public func deleteEntry(entryId: Int64) async throws {
        _ = try await rawRequest("time_entries/\(entryId)", method: "DELETE", query: [:], body: nil)
    }

    /// The fields of a time entry Harvest lets us write. Every one is
    /// optional: a PATCH sends only what it means to change, and the encoder
    /// leaves the rest out.
    private struct EntryFields: Encodable {
        var projectId: Int64?
        var taskId: Int64?
        var spentDate: Day?
        var hours: Double?
        var notes: String?
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await request(path, method: "GET", query: query, body: nil)
    }

    private func send<T: Decodable>(
        _ path: String,
        method: String,
        body: (some Encodable)? = Optional<EntryFields>.none
    ) async throws -> T {
        try await request(
            path,
            method: method,
            query: [:],
            body: try body.map(Self.encoder.encode)
        )
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        query: [String: String],
        body: Data?
    ) async throws -> T {
        let data = try await rawRequest(path, method: method, query: query, body: body)
        return try Self.decoder.decode(T.self, from: data)
    }

    private func rawRequest(
        _ path: String,
        method: String,
        query: [String: String],
        body: Data?
    ) async throws -> Data {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountId, forHTTPHeaderField: "Harvest-Account-ID")
        request.setValue("HarvestTimer (https://github.com/jdmcleod/harvest_but_good)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HarvestAPIError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299:
            return data
        case 401:
            throw HarvestAPIError.unauthorized
        case 403, 404:
            throw HarvestAPIError.accountMismatch
        default:
            throw HarvestAPIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
