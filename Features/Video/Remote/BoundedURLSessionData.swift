import Foundation

nonisolated enum BoundedURLSessionDataError: Error, Equatable, Sendable {
    case responseTooLarge
}

nonisolated enum BoundedURLSessionData {
    static func load(
        session: URLSession,
        request: URLRequest,
        maximumSize: Int,
        validateResponse: @Sendable (URLResponse) throws -> Void
    ) async throws -> (Data, URLResponse) {
        guard maximumSize > 0 else {
            throw BoundedURLSessionDataError.responseTooLarge
        }

        let (bytes, response) = try await session.bytes(for: request)
        let task = bytes.task
        do {
            try validateResponse(response)
            guard response.expectedContentLength < 0
                    || response.expectedContentLength <= Int64(maximumSize) else {
                throw BoundedURLSessionDataError.responseTooLarge
            }

            let data = try await withTaskCancellationHandler {
                var data = Data()
                if response.expectedContentLength > 0 {
                    data.reserveCapacity(Int(response.expectedContentLength))
                }

                for try await byte in bytes {
                    guard data.count < maximumSize else {
                        task.cancel()
                        throw BoundedURLSessionDataError.responseTooLarge
                    }
                    data.append(byte)
                }
                return data
            } onCancel: {
                task.cancel()
            }
            return (data, response)
        } catch {
            task.cancel()
            throw error
        }
    }
}
