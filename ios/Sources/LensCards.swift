import Combine
import Foundation
import MWDATDisplay

/// Renders Recall cards on the glasses lens. This file deliberately does
/// NOT import SwiftUI so the Display DSL names (Text, Button, FlexBox) stay
/// unambiguous — same convention as Meta's DisplayAccess sample.
///
/// display.send(_:) takes ONE root view and replaces the whole lens screen
/// (and its tap handlers). Neural Band pinches arrive as Button(onClick:) /
/// .onTap on the most recently sent view — so EVERY card here ships at least
/// one Button, otherwise a pinch does nothing at all.
///
/// Every send path also records why it did or didn't reach the lens in
/// `lensStatus`, which the Meet header and the Connect tab display. A blank
/// lens is now always explained.
@MainActor
final class ReminiCards: ObservableObject {
    static let shared = ReminiCards()

    /// Set by GlassesManager after addDisplay(); nilled on disconnect.
    var display: Display? {
        didSet { refreshStatus() }
    }
    /// Flips true when DisplayState.started arrives.
    var ready = false {
        didSet { refreshStatus() }
    }

    /// One line for the header pill: is the lens actually going to show this?
    @Published private(set) var lensStatus = "lens: idle — glasses not connected"
    /// Short label for the header pill.
    @Published private(set) var connected = false
    /// The last thing we tried to put on the lens, and whether it landed.
    @Published private(set) var lastSent = ""
    @Published private(set) var lastSendFailed = false

    /// Monotonic counter so a stale auto-clear never wipes a newer card.
    private var generation = 0
    /// Lines of the card currently on the lens, for the "more" pager.
    private var pagerLines: [String] = []
    private var pagerName = ""

    private init() {}

    // MARK: Status

    private func refreshStatus() {
        connected = (display != nil && ready)
        if display == nil {
            lensStatus = "lens: idle — glasses not connected"
        } else if !ready {
            lensStatus = "lens: attached but display not started yet"
        } else {
            lensStatus = "lens: connected"
        }
    }

    /// True when a send would actually reach the glasses.
    var canSend: Bool { display != nil && ready }

    /// Wraps every send so a blank lens is never a mystery.
    private func push(_ what: String, _ view: some DisplayableView) async {
        lastSent = what
        guard let display else {
            lastSendFailed = true
            lensStatus = "lens: “\(what)” not sent — no glasses attached (phone-only mode)"
            print("[recall] \(lensStatus)")
            return
        }
        guard ready, display.state == .started else {
            lastSendFailed = true
            lensStatus =
                "lens: “\(what)” not sent — display state is \(display.state), not .started"
            print("[recall] \(lensStatus)")
            return
        }
        do {
            try await display.send(view)
            lastSendFailed = false
            lensStatus = "lens: showing “\(what)”"
        } catch {
            lastSendFailed = true
            lensStatus = "lens: send failed — \(error.localizedDescription)"
            print("[recall] \(lensStatus)")
        }
    }

    /// The wordmark on the lens. The Display DSL has no per-run styling
    /// inside a single Text, so the brand's two-tone ghost is approximated
    /// with two runs on one row — `rec` in the dim secondary color, `all` in
    /// the primary. That matches the hardware variant's heavier ghost.
    private func wordmarkRow() -> FlexBox {
        FlexBox(direction: .row, spacing: 0) {
            Text("rec", style: .meta, color: .secondary)
            Text("all", style: .meta)
        }
    }

    /// Keeps a lens line short enough to read in a glance.
    private func trim(_ text: String, _ limit: Int = 90) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        let cut = clean.prefix(limit)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    // MARK: Cards

    /// The recall card: who they are as the heading, then one or two short
    /// lines of what to say next. Always has a Button so the Neural Band has
    /// something to select.
    func showRecall(
        headline: String, subhead: String = "", lines: [String], name: String
    ) async {
        generation += 1
        let gen = generation
        pagerLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        pagerName = name

        let heading = trim(
            headline.isEmpty ? (name.isEmpty ? "Someone you've met" : name) : headline,
            48
        )
        let role = trim(subhead, 48)
        let first = trim(pagerLines.first ?? "You've met before — no notes yet.")
        let second = pagerLines.count > 1 ? trim(pagerLines[1]) : ""
        let hasMore = pagerLines.count > 1

        await push(
            "recall · \(heading)",
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text(heading, style: .heading)
                if !role.isEmpty {
                    Text(role, style: .meta, color: .secondary)
                }
                Text(first, style: .body)
                if !second.isEmpty {
                    Text(second, style: .body, color: .secondary)
                }
                FlexBox(direction: .row, spacing: 8) {
                    Button(
                        label: hasMore ? "more" : "next",
                        style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.showLine(page: 1) }
                        }
                    )
                    Button(
                        label: "dismiss", style: .secondary, iconName: .checkmark,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.clear() }
                        }
                    )
                }
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 14, ifStill: gen)
    }

    /// Auto-enroll landed: this face is new and has just been added. Never a
    /// dead end — the lens always says something after a capture.
    func showNewFace(name: String, detail: String, merged: Bool) async {
        generation += 1
        let gen = generation
        let heading = trim(name.isEmpty ? "New face" : name, 48)
        let line = trim(
            detail.isEmpty
                ? (merged
                    ? "Face linked to what they just told you."
                    : "New face — added to your network.")
                : detail
        )

        await push(
            "new face · \(heading)",
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text(heading, style: .heading)
                Text(merged ? "face linked" : "new contact", style: .meta, color: .secondary)
                Text(line, style: .body)
                FlexBox(direction: .row, spacing: 8) {
                    Button(
                        label: "next", style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.showLine(page: 0) }
                        }
                    )
                    Button(
                        label: "dismiss", style: .secondary, iconName: .checkmark,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.clear() }
                        }
                    )
                }
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 12, ifStill: gen)
    }

    /// Something needs the wearer to do one small thing (move closer, better
    /// light). Friendly guidance, not an error.
    func showGuidance(_ text: String) async {
        generation += 1
        let gen = generation
        await push(
            "guidance",
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text("Try again", style: .heading)
                Text(trim(text, 120), style: .body)
                Button(
                    label: "ok", style: .primary, iconName: .checkmark,
                    onClick: { [weak self] in
                        Task { @MainActor in await self?.clear() }
                    }
                )
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 10, ifStill: gen)
    }

    /// A one-line note on the lens (ingest receipts, status).
    func showNote(_ text: String) async {
        generation += 1
        let gen = generation
        await push(
            "note",
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text(trim(text, 120), style: .body)
                Button(
                    label: "ok", style: .primary, iconName: .checkmark,
                    onClick: { [weak self] in
                        Task { @MainActor in await self?.clear() }
                    }
                )
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 8, ifStill: gen)
    }

    /// Page through the rest of the recall lines, one per screen.
    func showLine(page: Int) async {
        guard !pagerLines.isEmpty else {
            await showNote("Nothing more on file yet.")
            return
        }
        generation += 1
        let count = pagerLines.count
        let index = ((page % count) + count) % count
        let name = pagerName

        await push(
            "detail \(index + 1)/\(count)",
            FlexBox(direction: .column, spacing: 10) {
                Text(
                    name.isEmpty ? "talk about…" : "with \(name)…",
                    style: .meta, color: .secondary
                )
                Text(trim(pagerLines[index], 120), style: .body)
                FlexBox(direction: .row, spacing: 8) {
                    Button(
                        label: "next", style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in
                                await self?.showLine(page: index + 1)
                            }
                        }
                    )
                    Button(
                        label: "dismiss", style: .secondary, iconName: .checkmark,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.clear() }
                        }
                    )
                }
            }
            .padding(24)
            .background(.card)
        )
    }

    func clear() async {
        generation += 1
        guard let display, ready else { return }
        try? await display.clearDisplay()
        lensStatus = "lens: connected"
        lastSent = ""
    }

    private func scheduleClear(after seconds: Double, ifStill gen: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.generation == gen else { return }
            await self.clear()
        }
    }
}
