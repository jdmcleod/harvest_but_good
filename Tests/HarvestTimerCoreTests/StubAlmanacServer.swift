import Foundation

@testable import HarvestTimerCore

extension StubHarvestServer {
    /// A stand-in for almanac.rolemodel.dev, reusing the same request/reply
    /// plumbing built for Harvest above — only the credentials and the client
    /// on the other end differ.
    func almanacAPI(
        baseURL: String = "https://almanac.test",
        apiKey: String = "almanac-key",
        email: String = "ada@rolemodelsoftware.com"
    ) -> AlmanacAPI {
        AlmanacAPI(
            credentials: AlmanacCredentials(baseURL: baseURL, apiKey: apiKey, email: email),
            session: session()
        )
    }
}
