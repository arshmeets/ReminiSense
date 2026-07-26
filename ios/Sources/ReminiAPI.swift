import Foundation
import UIKit

// MARK: - Models

struct Whisper {
    let text: String
    let kind: String  // recognition | warning | reassurance
    let confidence: Double?
}

struct GlanceResult {
    let whisper: Whisper
    let matched: String
}

struct PersonCard {
    let name: String
    let md: String
}

struct PersonNode: Identifiable {
    let name: String
    let kind: String
    let pulse: Double
    var id: String { name }
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let ts: String
    let kind: String
    let text: String
}

// MARK: - API client

/// Client for the ReminiSense walker backend. Every endpoint is a JSON POST
/// whose response envelope is {"ok":true,"data":{"reports":[<payload>]}}.
/// JSONSerialization is used throughout so minor schema drift never crashes
/// the demo.
enum ReminiAPI {
    static let defaultBase = "http://10.104.8.45:8000"

    static var baseString: String {
        let stored = UserDefaults.standard.string(forKey: "reminiBaseURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var base = stored.isEmpty ? defaultBase : stored
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    enum APIError: LocalizedError {
        case badURL
        case server(status: Int, body: String)
        case backend(message: String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "The backend URL in Connect looks invalid."
            case let .server(status, body):
                let snippet = body.isEmpty ? "an empty body" : "“\(body)”"
                return "Server replied \(status) with \(snippet) — check the backend URL in Connect."
            case let .backend(message):
                return message
            }
        }
    }

    /// POSTs `body` to `path` and returns the first report payload.
    @discardableResult
    static func post(
        _ path: String, _ body: [String: Any] = [:]
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseString + path) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let snippet = String(decoding: data.prefix(200), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw APIError.server(status: status, body: snippet)
        }
        if let ok = json["ok"] as? Bool, !ok {
            let message = (json["error"] as? String)
                ?? (json["message"] as? String)
                ?? "The backend said no without a reason."
            throw APIError.backend(message: message)
        }
        let payload = ((json["data"] as? [String: Any])?["reports"]
            as? [[String: Any]])?.first
        return payload ?? [:]
    }

    // MARK: Endpoints

    static func glance(jpeg: Data) async throws -> GlanceResult {
        let payload = try await post("/walker/glance", [
            "image_b64": jpeg.base64EncodedString(),
            "source": "glasses",
        ])
        let whisperDict = payload["whisper"] as? [String: Any] ?? [:]
        let whisper = Whisper(
            text: whisperDict["text"] as? String ?? "",
            kind: whisperDict["kind"] as? String ?? "reassurance",
            confidence: (whisperDict["confidence"] as? NSNumber)?.doubleValue
        )
        return GlanceResult(
            whisper: whisper,
            matched: payload["matched"] as? String ?? ""
        )
    }

    static func personCard(name: String) async throws -> PersonCard {
        let payload = try await post("/walker/person_card", ["name": name])
        return PersonCard(
            name: payload["name"] as? String ?? name,
            md: payload["md"] as? String ?? ""
        )
    }

    /// "- " bullets under the "## Things to ask about" heading of the
    /// person card markdown — the lens "more" pager pages through these.
    static func askAboutBullets(name: String) async throws -> [String] {
        let md = try await personCard(name: name).md
        var bullets: [String] = []
        var inSection = false
        for rawLine in md.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                inSection = line.lowercased().contains("things to ask about")
                continue
            }
            if inSection, line.hasPrefix("- ") {
                bullets.append(String(line.dropFirst(2)))
            }
        }
        return bullets
    }

    static func enroll(
        name: String,
        relationship: String,
        notes: String,
        photoJpeg: Data?
    ) async throws {
        var body: [String: Any] = [
            "kind": "person",
            "name": name,
            "relationship": relationship,
            "notes": notes,
        ]
        if let photoJpeg {
            body["photo_b64"] = photoJpeg.base64EncodedString()
        }
        try await post("/walker/enroll", body)
    }

    static func people() async throws -> [PersonNode] {
        let payload = try await post("/walker/get_graph")
        let nodes = payload["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { node in
            let kind = (node["kind"] as? String ?? "").lowercased()
            guard kind == "person" else { return nil }
            let name = (node["name"] as? String)
                ?? (node["label"] as? String)
                ?? (node["id"] as? String)
            guard let name, !name.isEmpty else { return nil }
            let pulse = (node["pulse"] as? NSNumber)?.doubleValue ?? 0
            return PersonNode(name: name, kind: kind, pulse: pulse)
        }
    }

    static func timeline() async throws -> [TimelineEvent] {
        let payload = try await post("/walker/get_timeline")
        let events = payload["events"] as? [[String: Any]] ?? []
        return events.map { event in
            TimelineEvent(
                ts: "\(event["ts"] ?? "")",
                kind: event["kind"] as? String ?? "",
                text: event["text"] as? String ?? ""
            )
        }
    }

    static func forget(name: String) async throws {
        try await post("/walker/forget", ["name": name])
    }

    static func seedDemo() async throws {
        try await post("/walker/seed_demo")
    }

    static func resetDay() async throws {
        try await post("/walker/reset_day")
    }
}
