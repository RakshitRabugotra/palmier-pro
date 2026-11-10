import Combine
import Foundation
@preconcurrency import ConvexMobile

/// HTTP client for the palmier-pro-x local backend. Mirrors the Convex calls in `GenerationBackend`.
enum LocalBackend {
    private static let pollInterval: Duration = .seconds(1)

    @concurrent
    static func fetchCatalog(baseURL: URL) async throws -> [CatalogEntry] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "v1/models"))
        return try decode([CatalogEntry].self, data: data, response: response)
    }

    @concurrent
    static func uploadReference(fileURL: URL, contentType: String, baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/uploads"))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        return try decode(UploadResponse.self, data: data, response: response).url
    }

    @concurrent
    static func submit(
        model: String,
        params: BackendGenerationParams,
        projectId: String?,
        baseURL: URL
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/generations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SubmitRequest(model: model, params: params, projectId: projectId))
        let (data, response) = try await URLSession.shared.data(for: request)
        return try decode(SubmitResponse.self, data: data, response: response).jobId
    }

    /// Polls the job until it reaches a terminal state, matching the Convex `generations:byId` subscription.
    @MainActor
    static func jobUpdates(jobId: String, baseURL: URL) -> AnyPublisher<BackendGenerationJob?, ClientError> {
        Deferred {
            let subject = PassthroughSubject<BackendGenerationJob?, ClientError>()
            let task = Task { @MainActor in
                var loggedTransportFailure = false
                while !Task.isCancelled {
                    do {
                        let job = try await fetchJob(id: jobId, baseURL: baseURL)
                        subject.send(job)
                        if job.status == .succeeded || job.status == .failed {
                            subject.send(completion: .finished)
                            return
                        }
                    } catch BackendError.api(404, _, _) {
                        subject.send(missingJob(id: jobId))
                        subject.send(completion: .finished)
                        return
                    } catch {
                        // The backend may be restarting; keep polling until the subscriber cancels.
                        if !loggedTransportFailure {
                            loggedTransportFailure = true
                            Log.generation.warning("local backend poll failed job=\(jobId) error=\(error.localizedDescription)")
                        }
                    }
                    try? await Task.sleep(for: pollInterval)
                }
            }
            return subject.handleEvents(receiveCancel: { task.cancel() })
        }
        .eraseToAnyPublisher()
    }

    @concurrent
    private static func fetchJob(id: String, baseURL: URL) async throws -> BackendGenerationJob {
        let url = baseURL.appending(path: "v1/generations").appending(path: id)
        let (data, response) = try await URLSession.shared.data(from: url)
        return try decode(BackendGenerationJob.self, data: data, response: response)
    }

    private static func missingJob(id: String) -> BackendGenerationJob {
        BackendGenerationJob(
            _id: id,
            status: .failed,
            resultUrls: nil,
            errorMessage: "The local backend no longer has this generation.",
            costCredits: nil,
            refundedCredits: nil,
            completedAt: nil
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.transport("Non-HTTP response from the local backend")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw BackendError.api(status: http.statusCode, code: envelope.error.code, message: envelope.error.message)
            }
            throw BackendError.transport("Local backend returned HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct SubmitRequest: Encodable {
    let model: String
    let params: BackendGenerationParams
    let projectId: String?
}

private struct SubmitResponse: Decodable {
    let jobId: String
}

private struct UploadResponse: Decodable {
    let url: String
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}
