import Foundation
import MWDATDisplay

/// Renders Recall cards on the glasses lens. This file deliberately does
/// NOT import SwiftUI so the Display DSL names (Text, Button, FlexBox) stay
/// unambiguous — same convention as Meta's DisplayAccess sample.
///
/// display.send(_:) takes ONE root view and replaces the whole lens screen
/// (and its tap handlers). Neural Band pinches arrive as Button(onClick:) /
/// .onTap on the most recently sent view.
@MainActor
final class ReminiCards {
    static let shared = ReminiCards()

    /// Set by GlassesManager after addDisplay(); nilled on disconnect.
    var display: Display?
    /// Flips true when DisplayState.started arrives.
    var ready = false

    /// Monotonic counter so a stale auto-clear never wipes a newer card.
    private var generation = 0
    /// Lines of the card currently on the lens, for the "more" pager.
    private var pagerLines: [String] = []
    private var pagerName = ""

    private init() {}

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

    /// The recall card: headline as the heading, lines as the body, with a
    /// pager through the remaining lines behind "more".
    func showRecall(headline: String, lines: [String], name: String) async {
        guard ready, let display else { return }
        generation += 1
        let gen = generation
        pagerLines = lines
        pagerName = name

        let heading =
            headline.isEmpty
            ? (name.isEmpty ? "Someone you've met" : name) : headline
        let body = lines.first ?? ""

        if lines.count > 1 {
            try? await display.send(
                FlexBox(direction: .column, spacing: 10) {
                    wordmarkRow()
                    Text(heading, style: .heading)
                    Text(body, style: .body)
                    Button(
                        label: "more", style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.showLine(page: 1) }
                        }
                    )
                }
                .padding(24)
                .background(.card)
            )
        } else {
            try? await display.send(
                FlexBox(direction: .column, spacing: 10) {
                    wordmarkRow()
                    Text(heading, style: .heading)
                    Text(body, style: .body)
                }
                .padding(24)
                .background(.card)
            )
        }
        scheduleClear(after: 12, ifStill: gen)
    }

    /// No face matched — say nothing, show a quiet prompt instead.
    func showNoMatch() async {
        guard ready, let display else { return }
        generation += 1
        let gen = generation
        try? await display.send(
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text("New face — tap Listen to log the intro.", style: .body)
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 6, ifStill: gen)
    }

    /// A one-line note on the lens (ingest receipts, status).
    func showNote(_ text: String) async {
        guard ready, let display else { return }
        generation += 1
        let gen = generation
        try? await display.send(
            FlexBox(direction: .column, spacing: 10) {
                wordmarkRow()
                Text(text, style: .body)
            }
            .padding(24)
            .background(.card)
        )
        scheduleClear(after: 8, ifStill: gen)
    }

    /// Page through the rest of the recall lines, one per screen.
    func showLine(page: Int) async {
        guard ready, let display, !pagerLines.isEmpty else { return }
        generation += 1
        let count = pagerLines.count
        let index = ((page % count) + count) % count
        let name = pagerName

        try? await display.send(
            FlexBox(direction: .column, spacing: 10) {
                Text(
                    name.isEmpty ? "talk about…" : "with \(name)…",
                    style: .meta, color: .secondary
                )
                Text(pagerLines[index], style: .body)
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
                        label: "done", style: .secondary, iconName: .checkmark,
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
        guard let display else { return }
        try? await display.clearDisplay()
    }

    private func scheduleClear(after seconds: Double, ifStill gen: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.generation == gen else { return }
            await self.clear()
        }
    }
}
