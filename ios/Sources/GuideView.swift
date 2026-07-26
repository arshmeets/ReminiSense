import SwiftUI

/// The in-app user guide: how glancing works, what the lens cards mean,
/// the privacy promises, and demo instructions for judges.
struct GuideView: View {
    @State private var demoStatus: String?
    @State private var demoBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    glancingCard
                    lensCardsCard
                    privacyCard
                    judgesCard
                }
                .padding(20)
            }
            .background(Color.rsCream.ignoresSafeArea())
            .navigationTitle("Guide")
        }
    }

    // MARK: Sections

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A gentle memory, worn like glasses.")
                .font(.rsSerif(28))
                .foregroundStyle(Color.rsInk)
            Text(
                "ReminiSense quietly reintroduces the people, places, and routines that Alzheimer's blurs — a whisper in the ear and a soft card on the lens, exactly when it's needed, and never more than that."
            )
            .font(.rsBody)
            .foregroundStyle(Color.rsInkSoft)
        }
        .softCard()
    }

    private var glancingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("How glancing works", icon: "eye.fill")
            step(1, "Look at a person, a pill bottle, a doorway — anything uncertain.")
            step(2, "Tap the big Glance button (or let auto-glance watch along every few seconds).")
            step(3, "The glasses take one photo. It is matched on your care backend and immediately discarded.")
            step(4, "You get a whisper in your ear, a card on the lens, and a warm note in the app — a name, a relationship, one good thing to say.")
        }
        .softCard()
    }

    private var lensCardsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("What the lens cards mean", icon: "rectangle.on.rectangle")
            kindRow(
                "recognition",
                title: "Recognition",
                text: "A name in warm terracotta with one hook — “MAYA — your daughter. Ask about her pottery class.” Tap “more” to page through things to ask about. Fades on its own after 8 seconds."
            )
            kindRow(
                "warning",
                title: "Gentle warning",
                text: "“WAIT — you already took your morning pills.” Holds on the lens until you tap OK, because these are the moments that matter."
            )
            kindRow(
                "reassurance",
                title: "Reassurance",
                text: "Soft sage notes — “You're home. This is your kitchen.” They appear, breathe, and fade after 8 seconds."
            )
        }
        .softCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Our privacy promises", icon: "lock.heart")
            promise("Photos exist only for the moment of a glance — every frame is deleted the instant it's matched.")
            promise("No biometric templates ever leave your own care backend — nothing is sent to a cloud face service.")
            promise("Anyone can be forgotten. “Forget this person” erases their face signature and every memory, permanently.")
            promise("Nothing records continuously. A glance is one deliberate photo, never a video feed.")
        }
        .softCard()
    }

    private var judgesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("For judges — 90-second demo", icon: "sparkles")
            step(1, "Connect tab: point the backend URL at the demo Mac, then tap “Seed demo data” below.")
            step(2, "Glance tab: aim the phone (or glasses) at a teammate playing “Maya” and tap Glance — hear the whisper, watch the lens card, see the bubble.")
            step(3, "Glance at the pill bottle twice — the second time raises the WAIT card that holds until dismissed.")
            step(4, "People tab: open Maya's keepsake page, then show “Forget this person” — privacy is one tap deep, not buried.")

            HStack(spacing: 12) {
                Button {
                    Task { await runDemoAction("Seeding…") { try await ReminiAPI.seedDemo() } }
                } label: {
                    Label("Seed demo data", systemImage: "wand.and.stars")
                        .font(.rsCaption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.rsTerracotta)

                Button {
                    Task { await runDemoAction("Resetting…") { try await ReminiAPI.resetDay() } }
                } label: {
                    Label("Reset day", systemImage: "sunrise")
                        .font(.rsCaption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.rsInkSoft)
            }
            .disabled(demoBusy)

            if let demoStatus {
                Text(demoStatus)
                    .font(.rsCaption)
                    .foregroundStyle(
                        demoStatus.hasPrefix("Done") ? Color.rsSage : Color.rsInkSoft
                    )
            }
        }
        .softCard()
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.rsTerracotta)
            Text(title)
                .font(.rsSerif(22))
                .foregroundStyle(Color.rsInk)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.rsSerif(17))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.rsAmber))
            Text(text)
                .font(.rsBody)
                .foregroundStyle(Color.rsInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.rsSage)
            Text(text)
                .font(.rsBody)
                .foregroundStyle(Color.rsInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kindRow(_ kind: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(rsKindColor(kind))
                .frame(width: 10, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.rsBodyMedium)
                    .foregroundStyle(rsKindColor(kind))
                Text(text)
                    .font(.rsCaption)
                    .foregroundStyle(Color.rsInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runDemoAction(
        _ progress: String, _ action: @escaping () async throws -> Void
    ) async {
        demoBusy = true
        demoStatus = progress
        defer { demoBusy = false }
        do {
            try await action()
            demoStatus = "Done."
        } catch {
            demoStatus = "Failed: \(error.localizedDescription)"
        }
    }
}
