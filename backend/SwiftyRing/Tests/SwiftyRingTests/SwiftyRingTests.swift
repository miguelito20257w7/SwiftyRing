@testable import SwiftyRing
import VaporTesting
import Testing
import Fluent

@Suite("App Tests with DB", .serialized)
struct SwiftyRingTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Test Hello World Route")
    func helloWorld() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "hello", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string == "Hello, world!")
            })
        }
    }

    @Test("Test Route Registration and TrieRouter")
    func testRouteRegistration() async throws {
        let app = try await Application.make(.testing)
        do {
            try routes(app)
            _ = app.responder
            #expect(app.routes.all.count > 0)
            try await app.asyncShutdown()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }
}
