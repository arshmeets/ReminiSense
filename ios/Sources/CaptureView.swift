import SwiftUI

/// THE first half of the demo. One capture: a frame from the glasses (or the
/// iPhone), recognised against your network graph, answered with a recall
/// card — on the lens, in your ear, and in the app.
struct CaptureView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @EnvironmentObject private var speech: SpeechManager
    @AppStorage("reminiUsePhoneCamera") private var usePhoneCamera = false

    @State private var busy = false
    @State private var statusLine = ""
    @State private var cards: [RecallCard] = []
    @State private var lastCapture: UIImage?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    captureButton
                        .padding(.top, 10)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(glasses.isConnected && !usePhoneCamera
                                ? Color.rcAccent : Color.rcTextDim)
                            .frame(width: 6, height: 6)
                        Text(sourceLabel)
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcTextDim)
                    }

                    if let lastCapture {
                        Image(uiImage: lastCapture)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.rcLine, lineWidth: 1)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }

                    Toggle(isOn: $speech.speakAloud) {
                        Label("Speak the recall in my ear", systemImage: "waveform")
                            .font(.rcBodyMedium)
                            .foregroundStyle(Color.rcText)
                    }
                    .tint(.rcAccent)
                    .panel()

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcAlert)
                            .panel()
                    }

                    cardsList
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WordmarkLockup(size: 17)
                }
            }
        }
    }

    private var sourceLabel: String {
        if glasses.isConnected && !usePhoneCamera {
            return statusLine.isEmpty ? "Glasses camera" : statusLine
        }
        return statusLine.isEmpty ? "iPhone camera" : statusLine
    }

    private var captureButton: some View {
        Button {
            Task { await capture() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.rcAccent)
                    .shadow(color: Color.rcAccent.opacity(0.35), radius: 26, y: 8)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .padding(12)

                if busy {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 36, weight: .medium))
                        Text("Capture")
                            .font(.rcDisplay(24, .bold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(width: 200, height: 200)
            .scaleEffect(busy ? 0.95 : 1)
            .animation(.spring(duration: 0.4), value: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Capture — recognise who is in front of me")
    }

    private var cardsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if cards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.rcAccent)
                    Text("Recall cards land here.")
                        .font(.rcBodyMedium)
                        .foregroundStyle(Color.rcText)
                    Text("Point at someone you've met and hit Capture — you get their name, their company, and the one thing worth saying next.")
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcTextDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .padding(.horizontal, 8)
            } else {
                ForEach(cards.reversed()) { card in
                    RecallCardView(card: card)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.45), value: cards.count)
    }

    // MARK: Flow

    private func capture() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        defer { busy = false }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        statusLine = "Taking a frame…"

        guard
            let image = await glasses.capturePhoto(),
            let jpeg = image.jpegData(compressionQuality: 0.7)
        else {
            statusLine = ""
            errorText = "Couldn't take a photo — check the camera source in Connect."
            return
        }
        withAnimation { lastCapture = image }
        statusLine = "Matching against your network…"

        do {
            let recognition = try await RecallAPI.recognize(jpeg: jpeg)
            guard recognition.matched, !recognition.name.isEmpty else {
                statusLine = ""
                errorText = "No match in your network yet — use Listen to log the intro, or enroll their face from the Network tab."
                Task { await ReminiCards.shared.showNoMatch() }
                return
            }

            statusLine = "Recalling \(recognition.name)…"
            // The recall card carries the headline + talking points; the
            // recognition itself carries the spoken line for the ear.
            var card = (try? await RecallAPI.recall(name: recognition.name))
                ?? RecallCard.empty(name: recognition.name)
            if !card.found || card.headline.isEmpty {
                card = RecallCard(
                    found: true,
                    name: recognition.name,
                    org: recognition.org,
                    headline: recognition.title,
                    lines: recognition.spoken.isEmpty ? [] : [recognition.spoken],
                    topics: [], followups: [], history: []
                )
            }
            cards.append(card)
            statusLine = "Matched in \(recognition.elapsedMs) ms"

            // Ear: TTS, routed through the glasses speakers when connected.
            let spoken = recognition.spoken.isEmpty
                ? ([card.headline] + card.lines.prefix(1)).joined(separator: ". ")
                : recognition.spoken
            speech.speak(spoken)

            // Lens: the recall card on the glasses display.
            let headline = card.headline.isEmpty ? recognition.title : card.headline
            let lines = card.lines.isEmpty ? [recognition.spoken] : card.lines
            let name = card.name
            Task {
                await ReminiCards.shared.showRecall(
                    headline: headline, lines: lines, name: name
                )
            }
        } catch {
            statusLine = ""
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Recall card

struct RecallCardView: View {
    let card: RecallCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name)
                        .font(.rcDisplay(24))
                        .foregroundStyle(Color.rcText)
                    if !card.org.isEmpty {
                        Text(card.org)
                            .font(.rcCaption.weight(.medium))
                            .foregroundStyle(Color.rcAccent)
                    }
                }
                Spacer()
                Text(card.date, style: .time)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rcTextDim)
            }

            if !card.headline.isEmpty {
                Text(card.headline)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.rcText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !card.lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Say next", icon: "arrow.turn.down.right")
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(Color.rcAccent)
                                .frame(width: 5, height: 5)
                                .offset(y: -2)
                            Text(line)
                                .font(.rcBody)
                                .foregroundStyle(Color.rcText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !card.topics.isEmpty {
                FlowChips(items: card.topics)
            }

            if !card.followups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("You owe them", icon: "checklist")
                    ForEach(Array(card.followups.enumerated()), id: \.offset) { _, item in
                        Text("• \(item)")
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcTextDim)
                    }
                }
            }
        }
        .panel()
    }
}

/// Wrapping row of chips.
struct FlowChips: View {
    let items: [String]
    var tint: Color = .rcAccent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Chip(text: item, tint: tint)
                }
            }
        }
    }
}
