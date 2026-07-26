import Foundation
import UIKit

// MARK: - Models

/// One frame → who the graph thinks is in front of you.
struct Recognition {
    let matched: Bool
    let name: String
    let role: String
    let org: String
    /// The line the backend composed for the ear / lens.
    let spoken: String
    let score: Double
    let elapsedMs: Int

    var title: String {
        if name.isEmpty { return "No match" }
        if org.isEmpty { return name }
        return "\(name), \(org)"
    }
}

/// The recall card: who they are and what to say next.
struct RecallCard: Identifiable {
    let id = UUID()
    let found: Bool
    let name: String
    let org: String
    let headline: String
    let lines: [String]
    let topics: [String]
    let followups: [String]
    let history: [HistoryEntry]
    let date = Date()

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let when: String
        let what: String
        let kind: String
    }

    static func empty(name: String) -> RecallCard {
        RecallCard(
            found: false, name: name, org: "", headline: "",
            lines: [], topics: [], followups: [], history: []
        )
    }
}

/// What /walker/ingest pulled out of a conversation.
struct IngestReceipt: Identifiable {
    let id = UUID()
    let saved: String
    let newPerson: Bool
    let org: String
    let topics: [String]
    let newTopics: [String]
    let followups: [String]
    let date = Date()
}

/// Answer to "ask your network".
struct NetworkAnswer {
    struct Match: Identifiable {
        let id = UUID()
        let name: String
        let org: String
        let last: String
    }

    let matches: [Match]
    let reason: String
    let searched: Int
}

/// A row in the roster.
struct RosterPerson: Identifiable {
    let name: String
    let role: String
    let org: String
    let relationship: String
    let enrolledFace: Bool
    let encounters: Int

    var id: String { name }

    var subtitle: String {
        [role, org].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct PersonCard {
    let name: String
    let md: String
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let ts: String
    let kind: String
    let text: String
}

// MARK: - API client

/// Client for the deployed Recall graph backend. Every endpoint is a JSON
/// POST whose response envelope is
/// `{"ok":true,"data":{"reports":[<payload>], "result":{...}}}`.
/// JSONSerialization is used throughout and every field is optional-safe, so
/// minor schema drift degrades instead of crashing the demo.
enum RecallAPI {
    static let defaultBase = "https://jac.sodhiserver.com"

    static var baseString: String {
        let stored = UserDefaults.standard.string(forKey: "recallBaseURL")?
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
    /// Reports live at `data.reports[0]`; some walkers only fill
    /// `data.result.reports[0]`, so both are checked.
    @discardableResult
    static func post(
        _ path: String, _ body: [String: Any] = [:], timeout: TimeInterval = 60
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseString + path) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

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
        let container = json["data"] as? [String: Any] ?? [:]
        if let payload = (container["reports"] as? [[String: Any]])?.first {
            return payload
        }
        let result = container["result"] as? [String: Any] ?? [:]
        return (result["reports"] as? [[String: Any]])?.first ?? [:]
    }

    // MARK: Helpers

    private static func strings(_ any: Any?) -> [String] {
        (any as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func str(_ any: Any?) -> String {
        (any as? String) ?? ""
    }

    // MARK: Endpoints

    /// Face recognition from one frame.
    static func recognize(jpeg: Data) async throws -> Recognition {
        let payload = try await post(
            "/walker/Recognize", ["frame_b64": jpeg.base64EncodedString()],
            timeout: 90
        )
        return Recognition(
            matched: (payload["matched"] as? Bool) ?? false,
            name: str(payload["name"]),
            role: str(payload["role"]),
            org: str(payload["org"]),
            spoken: str(payload["spoken"]),
            score: (payload["score"] as? NSNumber)?.doubleValue ?? 0,
            elapsedMs: (payload["elapsed_ms"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// The recall card for a person — pass "last" for the most recent contact.
    static func recall(name: String = "last") async throws -> RecallCard {
        let payload = try await post("/walker/recall", ["name": name], timeout: 90)
        let history = (payload["history"] as? [[String: Any]] ?? []).map {
            RecallCard.HistoryEntry(
                when: str($0["when"]),
                what: str($0["what"]),
                kind: str($0["kind"])
            )
        }
        return RecallCard(
            found: (payload["found"] as? Bool) ?? false,
            name: str(payload["name"]).isEmpty ? name : str(payload["name"]),
            org: str(payload["org"]),
            headline: str(payload["headline"]),
            lines: strings(payload["lines"]),
            topics: strings(payload["topics"]),
            followups: strings(payload["followups"]),
            history: history
        )
    }

    /// Feed a conversation transcript into the graph.
    static func ingest(transcript: String) async throws -> IngestReceipt {
        let payload = try await post(
            "/walker/ingest", ["transcript": transcript], timeout: 120
        )
        return IngestReceipt(
            saved: str(payload["saved"]),
            newPerson: (payload["new_person"] as? Bool) ?? false,
            org: str(payload["org"]),
            topics: strings(payload["topics"]),
            newTopics: strings(payload["new_topics"]),
            followups: strings(payload["followups"])
        )
    }

    /// Free-text question over everyone you've met.
    static func query(question: String) async throws -> NetworkAnswer {
        let payload = try await post(
            "/walker/query", ["question": question], timeout: 120
        )
        let matches = (payload["matches"] as? [[String: Any]] ?? []).map {
            NetworkAnswer.Match(
                name: str($0["name"]),
                org: str($0["org"]),
                last: str($0["last"])
            )
        }
        return NetworkAnswer(
            matches: matches,
            reason: str(payload["reason"]),
            searched: (payload["searched"] as? NSNumber)?.intValue ?? matches.count
        )
    }

    /// Everyone in the graph. The backend can hold duplicate names after
    /// repeated seeding, so rows are merged by name here.
    static func roster() async throws -> [RosterPerson] {
        let payload = try await post("/walker/Roster")
        let rows = payload["people"] as? [[String: Any]] ?? []
        var order: [String] = []
        var merged: [String: RosterPerson] = [:]
        for row in rows {
            let name = str(row["name"])
            guard !name.isEmpty else { continue }
            let person = RosterPerson(
                name: name,
                role: str(row["role"]),
                org: str(row["org"]),
                relationship: str(row["relationship"]),
                enrolledFace: (row["enrolled_face"] as? Bool) ?? false,
                encounters: (row["encounters"] as? NSNumber)?.intValue ?? 0
            )
            if let existing = merged[name] {
                merged[name] = RosterPerson(
                    name: name,
                    role: existing.role.isEmpty ? person.role : existing.role,
                    org: existing.org.isEmpty ? person.org : existing.org,
                    relationship: existing.relationship.isEmpty
                        ? person.relationship : existing.relationship,
                    enrolledFace: existing.enrolledFace || person.enrolledFace,
                    encounters: max(existing.encounters, person.encounters)
                )
            } else {
                merged[name] = person
                order.append(name)
            }
        }
        return order.compactMap { merged[$0] }
    }

    /// Attach a face to a person — creates them if they aren't in the graph.
    @discardableResult
    static func enroll(
        name: String,
        role: String,
        org: String,
        relationship: String,
        notes: String = "",
        photoJpeg: Data
    ) async throws -> String {
        let payload = try await post(
            "/walker/Enroll",
            [
                "name": name,
                "frame_b64": photoJpeg.base64EncodedString(),
                "role": role,
                "org": org,
                "relationship": relationship,
                "notes": notes,
            ],
            timeout: 120
        )
        if (payload["enrolled"] as? Bool) == true {
            let attached = (payload["attached_to_existing"] as? Bool) ?? false
            return attached
                ? "Face attached to \(str(payload["name"]))'s existing record."
                : "\(str(payload["name"])) added to your network."
        }
        let reason = str(payload["reason"])
        throw APIError.backend(
            message: reason.isEmpty ? "Enrollment failed." : reason.capitalizedFirst
        )
    }

    static func personCard(name: String) async throws -> PersonCard {
        let payload = try await post("/walker/person_card", ["name": name], timeout: 90)
        return PersonCard(
            name: str(payload["name"]).isEmpty ? name : str(payload["name"]),
            md: str(payload["md"])
        )
    }

    static func timeline() async throws -> [TimelineEvent] {
        let payload = try await post("/walker/get_timeline")
        let events = payload["events"] as? [[String: Any]] ?? []
        return events.map {
            TimelineEvent(
                ts: str($0["ts"]),
                kind: str($0["kind"]),
                text: str($0["text"])
            )
        }
    }

    /// Live caption line for the lens.
    static func caption(text: String, lang: String = "en") async throws -> String {
        let payload = try await post(
            "/walker/caption", ["text": text, "lang": lang], timeout: 60
        )
        return str(payload["display_text"])
    }

    static func forget(name: String) async throws {
        try await post("/walker/forget", ["name": name])
    }

    static func seed() async throws {
        try await post("/walker/Seed", [:], timeout: 120)
    }

    static func reset() async throws {
        try await post("/walker/Reset", [:], timeout: 120)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
