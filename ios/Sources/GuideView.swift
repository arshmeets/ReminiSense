import SwiftUI

/// The in-app guide: how Capture and Listen work, what the lens card means,
/// the privacy posture, and the judge demo script with Seed / Reset.
struct GuideView: View {
    @State private var demoStatus: String?
    @State private var demoBusy = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    loopCard
                    lensCard
                    privacyCard
                    judgesCard
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Sections

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Wordmark(size: 40)
            Text("your network, remembered")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.rcAccent)
            Text(
                "You meet forty people at a summit and remember four. Recall is the memory layer that keeps the other thirty-six: every intro is captured, structured into a graph, and handed back the second you see that face again — a name, a company, and the one line worth opening with."
            )
            .font(.rcBody)
            .foregroundStyle(Color.rcTextDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        .panel()
    }

    private var loopCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("The loop", icon: "arrow.triangle.2.circlepath")
            step(1, "**Listen.** Hold the mic while someone introduces themselves. The transcript runs live on screen; on release it goes to the graph, which pulls out their name, company, what you discussed, and what you promised them.")
            step(2, "**Capture.** Point at a face and tap. One frame goes to the backend, gets matched against the faces you've enrolled, and comes back as a recall card.")
            step(3, "**Recall.** The card lands three places at once — on the glasses lens, in your ear over the speakers, and in the app so you can scroll it later.")
            step(4, "**Ask.** In Network, ask the graph in plain language: “who did I meet working on payments?” It answers with the people and the reason they match.")
        }
        .panel()
    }

    private var lensCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("What lands on the lens", icon: "eyeglasses")

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 0) {
                    Text("rec").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.rcText.opacity(0.45))
                    Text("all").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rcText)
                }
                Text("Nadia Rahman, Loopwire")
                    .font(.rcDisplay(19, .bold))
                    .foregroundStyle(Color.rcText)
                Text("Discussed fintech, payments, and seed round fundraising")
                    .font(.rcBody)
                    .foregroundStyle(Color.rcTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                Chip(text: "more ▸", tint: .rcAccent, filled: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rcSurfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            bullet("The heading is who they are: name and company, straight from the graph.")
            bullet("The body is the highest-value thing to say next — a topic you already covered, or a follow-up you owe them.")
            bullet("“more” pages through the rest of the talking points; a Neural Band pinch advances it. The card clears itself after twelve seconds so it never sits in your eyeline mid-conversation.")
            bullet("No match means no card and no audio. A wrong name is worse than silence.")
        }
        .panel()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Privacy", icon: "lock.shield")
            promise("No biometric database. A face becomes a 128-dimension vector on your own backend; the photo is matched and dropped, never stored, never sent to a third-party face service.")
            promise("Transcripts are sanitised before storage. What lands in the graph is structured contact detail — name, company, topics, follow-ups — not the raw audio and not the verbatim conversation.")
            promise("Forget is one call. “Forget” on any contact deletes their vector, notes and every encounter. No tombstone, no soft delete.")
            promise("Nothing runs continuously. Capture is one deliberate frame; Listen only records while your thumb is on the button.")
            promise("Enrollment is consented. Someone's face only enters the graph when you deliberately add it with them in front of you.")
        }
        .panel()
    }

    private var judgesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("For judges — 90 seconds", icon: "sparkles")
            step(1, "Tap **Seed the demo graph** below — that loads a few founders and investors so the network isn't empty.")
            step(2, "**Listen tab:** hold the mic and have someone say “Hi, I'm Dana, I run growth at Ledgerloop, we do embedded payments — send me the API docs next week.” Release. The receipt shows the person, the company, the topics, and the follow-up the graph just learned.")
            step(3, "**Network tab:** pull to refresh — Dana is there. Tap **+**, enroll their face with the camera.")
            step(4, "**Capture tab:** point at them and tap. The recall card comes back on the lens, in your ear, and on screen — with the fintech thread they just mentioned.")
            step(5, "**Network tab:** ask “who did I meet working on payments?” — the graph reasons over everyone and explains the match.")
            step(6, "**Contact page → Forget** to show the privacy story in one tap.")

            HStack(spacing: 10) {
                Button {
                    Task { await runDemoAction("Seeding…") { try await RecallAPI.seed() } }
                } label: {
                    Label("Seed the demo graph", systemImage: "wand.and.stars")
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAccent))

                Button {
                    confirmReset = true
                } label: {
                    Label("Reset", systemImage: "trash")
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAlert))
            }
            .disabled(demoBusy)

            if let demoStatus {
                Text(demoStatus)
                    .font(.rcCaption)
                    .foregroundStyle(
                        demoStatus.hasPrefix("Done") ? Color.rcAccent : Color.rcTextDim
                    )
            }

            Text("Reset empties the whole graph. Seed after resetting to get the demo cast back.")
                .font(.system(size: 12))
                .foregroundStyle(Color.rcTextDim)
        }
        .panel()
        .alert("Empty the graph?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                Task { await runDemoAction("Resetting…") { try await RecallAPI.reset() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every person, face and encounter is deleted from the backend.")
        }
    }

    // MARK: Pieces

    private func step(_ number: Int, _ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.rcAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.rcAccent.opacity(0.15)))
            Text(inline(markdown))
                .font(.rcBody)
                .foregroundStyle(Color.rcText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.rcAccent)
            Text(text)
                .font(.rcBody)
                .foregroundStyle(Color.rcText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Circle()
                .fill(Color.rcAccent)
                .frame(width: 5, height: 5)
                .offset(y: -2)
            Text(text)
                .font(.rcCaption)
                .foregroundStyle(Color.rcTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
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
