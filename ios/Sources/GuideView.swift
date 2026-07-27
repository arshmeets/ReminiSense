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
                    bandCard
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
            SectionLabel("The loop — one tap", icon: "arrow.triangle.2.circlepath")
            step(1, "**Meet.** One button. Recall takes a frame, then listens for about eight seconds while they introduce themselves. Camera first, microphone second — they never contend for the audio route.")
            step(2, "**Recognise or remember.** The frame is matched against every face you've enrolled. A hit becomes a recall card. A miss is *not* a dead end: the same frame is enrolled on the spot, named from what they just said, or as a placeholder you rename later.")
            step(3, "**Autofill.** The transcript goes to the graph, which pulls out their company, the topics you covered and anything you promised them — and pins it to the face you just captured.")
            step(4, "**Answer.** The card lands three places at once: on the glasses lens, in your ear over the speakers, and in the app.")
            step(5, "**Ask.** In Network, ask the graph in plain language: “who did I meet working on payments?” It answers with the people and the reason they match.")
            bullet("“Keep going” repeats the whole loop hands-free — walk a room and Recall builds the graph as you go.")
            bullet("The Manual tab still has single-shot Capture and press-and-hold Listen for when you want to isolate one half.")
        }
        .panel()
    }

    private var bandCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("The Neural Band", icon: "hand.point.up.left.fill")
            Text("What a pinch actually does — worth being precise about, because the SDK is narrower than people assume.")
                .font(.rcCaption)
                .foregroundStyle(Color.rcTextDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Can")
                bullet("Select whatever is on the lens right now. Every Recall card ships with buttons — “more”/“next” to page the talking points and “dismiss” to clear — so a pinch always has a target.")
                bullet("Page through the rest of a person's talking points without touching the phone.")
                bullet("Dismiss a card early so it isn't sitting in your eyeline mid-handshake.")
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Cannot")
                bullet("Start a capture. DAT 0.8 exposes the band only as selection on the most recently sent lens view — there is no free-standing gesture event, so the loop is still kicked off from the phone (or left on “keep going”).")
                bullet("Scroll, swipe, or handle raw EMG. The app sees a tap on a Button, nothing lower level.")
                bullet("Reach a card that has no Button on it. A lens view sent without one swallows the pinch entirely — which is why every card here has at least one.")
                bullet("Do anything while the display is not in the started state. Connect shows that state verbatim.")
            }
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

            bullet("The heading is who they are: name, then role and company underneath, straight from the graph.")
            bullet("The body is the highest-value thing to say next — a topic you already covered, or a follow-up you owe them. One or two lines, never a wall.")
            bullet("“more” pages through the rest of the talking points; a Neural Band pinch advances it. “dismiss” clears it. The card clears itself after fourteen seconds anyway.")
            bullet("A face Recall doesn't know gets a “new contact” card instead — it has been added to your network, and the lens says so. There is no such thing as a capture that shows nothing.")
            bullet("If the frame had no detectable face, the lens says exactly that and tells you to get closer. Recall still never guesses a name out loud — a wrong name is worse than silence.")
        }
        .panel()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Privacy", icon: "lock.shield")
            promise("No biometric database. A face becomes a 128-dimension vector on your own backend; the photo is matched and dropped, never stored, never sent to a third-party face service.")
            promise("Transcripts are sanitised before storage. What lands in the graph is structured contact detail — name, company, topics, follow-ups — not the raw audio and not the verbatim conversation.")
            promise("Forget is one call. “Forget” on any contact deletes their vector, notes and every encounter. No tombstone, no soft delete.")
            promise("Nothing runs continuously by default. Meet is one deliberate tap: one frame, one fixed listening window. “Keep going” is opt-in and visible while it's on.")
            promise("Auto-enroll is still your action. A face only enters the graph on a capture you triggered, with them in front of you — Recall just stops making you fill in a form first. Forget removes it as completely as any other contact.")
        }
        .panel()
    }

    private var judgesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("For judges — 90 seconds", icon: "sparkles")
            step(1, "Tap **Seed the demo graph** below — that loads a few founders and investors so the network isn't empty.")
            step(2, "**Meet tab:** point at someone new and tap once. While it listens, have them say “Hi, I'm Dana, I run growth at Ledgerloop, we do embedded payments — send me the API docs next week.” Recall doesn't know the face, so it enrols it as Dana on the spot and shows a new-contact card on the lens.")
            step(3, "**Meet again, same person.** Now it's a hit: the lens shows “Dana Okafor / Growth, Ledgerloop” with the embedded-payments thread and the API-docs follow-up, and the same line goes into your ear.")
            step(4, "**Neural Band:** pinch to page to the next talking point, pinch “dismiss” to clear it. Every card has buttons, so the band always does something.")
            step(5, "**Network tab:** ask “who did I meet working on payments?” — the graph reasons over everyone and explains the match. Anyone auto-enrolled without a name is badged **NAME ME**; open them and give them a real name.")
            step(6, "**Contact page → Forget** to show the privacy story in one tap.")
            bullet("If the room is loud, flip on **Keep going** and just walk — the loop repeats itself.")

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
