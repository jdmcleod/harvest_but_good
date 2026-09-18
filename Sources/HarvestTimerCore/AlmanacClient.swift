import Foundation

/// Everything the app asks of Almanac: who you are there, the pace it has
/// worked out for you this quarter, and the time off ahead that pace already
/// accounts for. `AlmanacAPI` talks to the real service; tests stand in their
/// own conformance.
public protocol AlmanacClient {
    func people() async throws -> [AlmanacPerson]
    func totalPace(personId: String) async throws -> AlmanacPace
    func constraints(email: String) async throws -> [AlmanacConstraint]
}
