import Foundation

public enum AidokuHTTPClient {
    private static let globalPermits = AidokuHTTPPermitPool(limit: 12)

    public static func data(
        for request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool? = nil,
        usesSystemProxy: Bool = true,
        responseObserver: (@Sendable (HTTPURLResponse) -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes > 0 else { throw AidokuRuntimeError.responseTooLarge }
        return try await globalPermits.withPermit {
            let transaction = AidokuBoundedHTTPTransaction(
                request: request,
                maximumBytes: maximumBytes,
                insecureTransportApproved: insecureTransportApproved,
                usesSystemProxy: usesSystemProxy,
                responseObserver: responseObserver
            )
            return try await withTaskCancellationHandler {
                try await transaction.value()
            } onCancel: {
                transaction.cancel()
            }
        }
    }
}

private actor AidokuHTTPPermitPool {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var permits: Int
    private var waiters: [Waiter] = []

    init(limit: Int) { permits = max(1, limit) }

    func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if permits > 0 {
            permits -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

private final class AidokuBoundedHTTPTransaction: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let request: URLRequest
    private let maximumBytes: Int
    private let insecureTransportApproved: Bool?
    private let usesSystemProxy: Bool
    private let responseObserver: (@Sendable (HTTPURLResponse) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var completed = false

    init(
        request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool?,
        usesSystemProxy: Bool,
        responseObserver: (@Sendable (HTTPURLResponse) -> Void)?
    ) {
        self.request = request
        self.maximumBytes = maximumBytes
        self.insecureTransportApproved = insecureTransportApproved
        self.usesSystemProxy = usesSystemProxy
        self.responseObserver = responseObserver
    }

    func value() async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                guard !completed else {
                    continuation.resume(throwing: AidokuRuntimeError.cancelled)
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                if !usesSystemProxy { configuration.connectionProxyDictionary = [:] }
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        }
    }

    func cancel() {
        let task = lock.withLock { self.task }
        task?.cancel()
        finish(.failure(AidokuRuntimeError.cancelled))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if isAllowed(response.url) {
            responseObserver?(response)
        }
        completionHandler(isAllowed(request.url) ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              isAllowed(response.url),
              response.expectedContentLength < 0 || response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(AidokuRuntimeError.responseTooLarge))
            return
        }
        responseObserver?(response)
        lock.withLock { self.response = response }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let accepted = lock.withLock { () -> Bool in
            guard !completed, data.count <= maximumBytes - chunk.count else { return false }
            data.append(chunk)
            return true
        }
        if !accepted {
            dataTask.cancel()
            finish(.failure(AidokuRuntimeError.responseTooLarge))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure((error as? URLError)?.code == .cancelled ? AidokuRuntimeError.cancelled : error))
            return
        }
        let result = lock.withLock { () -> Result<(Data, HTTPURLResponse), Error> in
            guard let response else { return .failure(AidokuRuntimeError.runtimeFailure("Missing HTTP response")) }
            return .success((data, response))
        }
        finish(result)
    }

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        guard let insecureTransportApproved else { return true }
        return (try? AidokuSourceListParser.validateRemoteURL(
            url,
            insecureTransportConfirmed: insecureTransportApproved
        )) != nil
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<(Data, HTTPURLResponse), Error>? in
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        guard let continuation else { return }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

private extension NSLocking {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
