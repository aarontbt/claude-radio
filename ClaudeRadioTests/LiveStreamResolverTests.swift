import XCTest
@testable import ClaudeRadio

final class LiveStreamResolverTests: XCTestCase {
    // MARK: - extractVideoID

    func testExtractVideoIDFromCanonicalLink() {
        let html = """
        <html><head>
        <link rel="canonical" href="https://www.youtube.com/watch?v=tRsQsTMvPNg">
        </head><body></body></html>
        """
        XCTAssertEqual(LiveStreamResolver.extractVideoID(fromHTML: html), "tRsQsTMvPNg")
    }

    func testExtractVideoIDWithHyphenAndUnderscore() {
        let html = """
        <link rel="canonical" href="https://www.youtube.com/watch?v=a-B_c1D2e3F">
        """
        XCTAssertEqual(LiveStreamResolver.extractVideoID(fromHTML: html), "a-B_c1D2e3F")
    }

    func testExtractVideoIDReturnsNilWhenChannelOffline() {
        let html = """
        <link rel="canonical" href="https://www.youtube.com/channel/UCV03SRZXJEz-hchIAogeJOg">
        """
        XCTAssertNil(LiveStreamResolver.extractVideoID(fromHTML: html))
    }

    func testExtractVideoIDReturnsNilForEmptyOrConsentHTML() {
        XCTAssertNil(LiveStreamResolver.extractVideoID(fromHTML: ""))
        XCTAssertNil(LiveStreamResolver.extractVideoID(fromHTML: "<html><body>Before you continue to YouTube</body></html>"))
    }

    func testExtractVideoIDIgnoresNonCanonicalWatchLinks() {
        let html = """
        <a href="https://www.youtube.com/watch?v=shouldNotMatch">related video</a>
        """
        XCTAssertNil(LiveStreamResolver.extractVideoID(fromHTML: html))
    }

    // MARK: - resolveLiveVideoID

    func testResolveThrowsOnBadStatus() async {
        let session = Self.stubbedSession(statusCode: 404, body: "")
        let resolver = LiveStreamResolver(session: session)
        await XCTAssertThrowsErrorAsync(try await resolver.resolveLiveVideoID()) { error in
            guard case LiveStreamResolver.ResolverError.badStatus(let code) = error else {
                return XCTFail("expected badStatus, got \(error)")
            }
            XCTAssertEqual(code, 404)
        }
    }

    func testResolveThrowsWhenNoCanonicalVideoID() async {
        let session = Self.stubbedSession(statusCode: 200, body: "<html><body>offline</body></html>")
        let resolver = LiveStreamResolver(session: session)
        await XCTAssertThrowsErrorAsync(try await resolver.resolveLiveVideoID()) { error in
            guard case LiveStreamResolver.ResolverError.noVideoID = error else {
                return XCTFail("expected noVideoID, got \(error)")
            }
        }
    }

    func testResolveReturnsVideoIDOnSuccess() async throws {
        let html = """
        <link rel="canonical" href="https://www.youtube.com/watch?v=tRsQsTMvPNg">
        """
        let session = Self.stubbedSession(statusCode: 200, body: html)
        let resolver = LiveStreamResolver(session: session)
        let videoID = try await resolver.resolveLiveVideoID()
        XCTAssertEqual(videoID, "tRsQsTMvPNg")
    }

    // MARK: - Stub plumbing

    private static func stubbedSession(statusCode: Int, body: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.statusCode = statusCode
        StubURLProtocol.body = body
        return URLSession(configuration: config)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
