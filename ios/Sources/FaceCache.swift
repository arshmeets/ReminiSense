import Foundation
import UIKit

/// Keeps the reference frame that was used to auto-enrol someone.
///
/// The backend has no rename walker — renaming means re-`Enroll`ing under the
/// real name and forgetting the placeholder — so the app has to be able to
/// replay the original frame later. Frames live in Application Support, keyed
/// by the name they were enrolled under, and survive a relaunch mid-demo.
enum FaceCache {
    private static let folderName = "recall-faces"

    private static var folder: URL? {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return nil }
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    private static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = name.lowercased().unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        }
        return String(scalars)
    }

    private static func url(for name: String) -> URL? {
        folder?.appendingPathComponent("\(slug(name)).jpg")
    }

    /// Decoded frames, so a roster of avatars doesn't hit the disk on every
    /// SwiftUI body evaluation. Invalidated whenever the file behind a name
    /// changes, which is the only way the picture can go stale.
    private static let decoded = NSCache<NSString, UIImage>()

    static func store(_ jpeg: Data, for name: String) {
        guard let url = url(for: name) else { return }
        try? jpeg.write(to: url, options: .atomic)
        decoded.removeObject(forKey: name as NSString)
    }

    static func frame(for name: String) -> Data? {
        guard let url = url(for: name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func image(for name: String) -> UIImage? {
        if let hit = decoded.object(forKey: name as NSString) { return hit }
        guard let image = frame(for: name).flatMap(UIImage.init(data:)) else {
            return nil
        }
        decoded.setObject(image, forKey: name as NSString)
        return image
    }

    /// Re-key a stored frame — used when a placeholder turns out to have a real
    /// name, so the avatar follows the person instead of being orphaned under
    /// "New contact 03".
    static func move(from old: String, to new: String) {
        guard old.caseInsensitiveCompare(new) != .orderedSame,
              let jpeg = frame(for: old)
        else { return }
        store(jpeg, for: new)
        forget(old)
    }

    static func forget(_ name: String) {
        decoded.removeObject(forKey: name as NSString)
        guard let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Placeholder names

    private static let counterKey = "recallAutoEnrollCounter"
    /// Names of everyone auto-enrolled under a placeholder, so the Network tab
    /// can offer "give this person a real name".
    private static let placeholderKey = "recallPlaceholderNames"

    /// Zero-padded on purpose: `forget` on the backend also matches a name that
    /// is a *substring* of another person's, so "New contact 1" would take
    /// "New contact 10" down with it. "New contact 01" cannot be a prefix of
    /// "New contact 02".
    static func nextPlaceholderName() -> String {
        let defaults = UserDefaults.standard
        let next = defaults.integer(forKey: counterKey) + 1
        defaults.set(next, forKey: counterKey)
        return String(format: "New contact %02d", next)
    }

    static func markPlaceholder(_ name: String) {
        var names = placeholderNames
        guard !names.contains(name) else { return }
        names.append(name)
        UserDefaults.standard.set(names, forKey: placeholderKey)
    }

    static func clearPlaceholder(_ name: String) {
        let names = placeholderNames.filter { $0 != name }
        UserDefaults.standard.set(names, forKey: placeholderKey)
    }

    static var placeholderNames: [String] {
        UserDefaults.standard.stringArray(forKey: placeholderKey) ?? []
    }

    static func isPlaceholder(_ name: String) -> Bool {
        placeholderNames.contains(name)
            || name.range(of: #"^New contact \d"#, options: .regularExpression) != nil
    }

    /// The one rule for "did the conversation actually tell us who this is?".
    ///
    /// `ingest` reports `saved: ""` when nobody introduced themselves, and it
    /// echoes back the placeholder itself when the walk was pinned to one with
    /// `speaker`. Neither counts as a real name, and treating the second as one
    /// is what let "New contact 03" keep collecting topics under its auto-name.
    static func usableRealName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count > 1, !isPlaceholder(name) else { return nil }
        // Guard against the extractor handing back a non-answer.
        let junk = ["unknown", "unnamed", "n/a", "none", "someone", "speaker"]
        guard !junk.contains(name.lowercased()) else { return nil }
        return name
    }
}
