import Foundation
import MWDATDisplay

/// Renders whisper cards on the glasses lens. This file deliberately does
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
    private var bulletsCache: [String: [String]] = [:]

    private init() {}

    func show(text: String, kind: String, matched: String) async {
        guard ready, let display else { return }
        generation += 1
        let gen = generation

        switch kind {
        case "recognition":
            let name = matched.isEmpty ? "Someone you know" : matched
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text(name.uppercased(), style: .heading)
                    Text(text, style: .body)
                    Button(
                        label: "more", style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in
                                await self?.showAskAbout(name: name, page: 0)
                            }
                        }
                    )
                }
                .padding(24)
                .background(.card)
            )
            scheduleClear(after: 8, ifStill: gen)

        case "warning":  // e.g. double dose — holds until dismissed
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text("WAIT", style: .heading)
                    Text(text, style: .body)
                    Button(
                        label: "OK", style: .primary, iconName: .checkmark,
                        onClick: { [weak self] in
                            Task { @MainActor in await self?.clear() }
                        }
                    )
                }
                .padding(24)
                .background(.card)
            )

        default:  // reassurance / object
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text(text, style: .body)
                }
                .padding(24)
                .background(.card)
            )
            scheduleClear(after: 8, ifStill: gen)
        }
    }

    /// "more" = the person card MD distilled: page through the
    /// "Things to ask about" bullets, one per screen.
    func showAskAbout(name: String, page: Int) async {
        guard ready, let display else { return }
        var bullets = bulletsCache[name] ?? []
        if bullets.isEmpty {
            bullets = (try? await ReminiAPI.askAboutBullets(name: name)) ?? []
            bulletsCache[name] = bullets
        }
        guard !bullets.isEmpty else { return }
        generation += 1
        let count = bullets.count
        let index = ((page % count) + count) % count

        try? await display.send(
            FlexBox(direction: .column, spacing: 12) {
                Text("ask \(name) about…", style: .meta, color: .secondary)
                Text(bullets[index], style: .body)
                FlexBox(direction: .row, spacing: 8) {
                    Button(
                        label: "next", style: .primary,
                        iconName: .triangleRightVerticalLine,
                        onClick: { [weak self] in
                            Task { @MainActor in
                                await self?.showAskAbout(name: name, page: index + 1)
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
