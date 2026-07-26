import SwiftUI

struct WhisperBubble: Identifiable {
    let id = UUID()
    let text: String
    let kind: String
    let matched: String
    let date = Date()
}

/// THE DEMO. One giant warm button: capture what the wearer is looking at,
/// let the backend recognize it, then whisper the answer in the ear, on the
/// lens, and in the app.
struct GlanceView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @EnvironmentObject private var speech: SpeechManager
    @AppStorage("reminiUsePhoneCamera") private var usePhoneCamera = false

    @State private var busy = false
    @State private var autoGlance = false
    @State private var autoTask: Task<Void, Never>?
    @State private var bubbles: [WhisperBubble] = []
    @State private var lastCapture: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        glanceButton
                            .padding(.top, 18)

                        Text(sourceLabel)
                            .font(.rsCaption)
                            .foregroundStyle(Color.rsInkSoft)

                        controlsRow

                        if let lastCapture {
                            Image(uiImage: lastCapture)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.rsAmber.opacity(0.5), lineWidth: 1.5)
                                )
                                .transition(.scale.combined(with: .opacity))
                        }

                        bubblesList
                    }
                    .padding(20)
                }
            }
            .background(Color.rsCream.ignoresSafeArea())
            .navigationTitle("Glance")
        }
        .onDisappear {
            autoGlance = false
            stopAutoGlance()
        }
    }

    private var sourceLabel: String {
        if glasses.isConnected && !usePhoneCamera {
            return "Looking through your glasses"
        }
        return "Using the iPhone camera"
    }

    private var glanceButton: some View {
        Button {
            Task { await performGlance() }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.rsAmber, .rsTerracotta],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.rsTerracotta.opacity(0.35), radius: 22, y: 10)

                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                    .padding(10)

                if busy {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 40))
                        Text("Glance")
                            .font(.rsSerif(34))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(width: 220, height: 220)
            .scaleEffect(busy ? 0.94 : 1)
            .animation(.spring(duration: 0.45), value: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Glance — take a look and tell me who or what I'm seeing")
    }

    private var controlsRow: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $autoGlance) {
                Label("Auto-glance every 6 seconds", systemImage: "arrow.triangle.2.circlepath")
                    .font(.rsBodyMedium)
                    .foregroundStyle(Color.rsInk)
            }
            .tint(.rsTerracotta)

            Toggle(isOn: $speech.speakAloud) {
                Label("Whisper out loud", systemImage: "speaker.wave.2.fill")
                    .font(.rsBodyMedium)
                    .foregroundStyle(Color.rsInk)
            }
            .tint(.rsTerracotta)
        }
        .softCard()
        .onChange(of: autoGlance) { _, on in
            stopAutoGlance()
            if on {
                autoTask = Task {
                    while !Task.isCancelled {
                        await performGlance()
                        try? await Task.sleep(for: .seconds(6))
                    }
                }
            }
        }
    }

    private var bubblesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if bubbles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.rsAmber)
                    Text("Whispers will appear here.")
                        .font(.rsBody)
                        .foregroundStyle(Color.rsInkSoft)
                    Text("Tap Glance while looking at someone you know.")
                        .font(.rsCaption)
                        .foregroundStyle(Color.rsInkSoft.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(bubbles.reversed()) { bubble in
                    bubbleView(bubble)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.5), value: bubbles.count)
    }

    private func bubbleView(_ bubble: WhisperBubble) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: rsKindIcon(bubble.kind))
                    .font(.system(size: 13))
                Text(bubble.matched.isEmpty ? bubble.kind.capitalized : bubble.matched)
                    .font(.rsCaption.weight(.semibold))
                Spacer()
                Text(bubble.date, style: .time)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rsInkSoft)
            }
            .foregroundStyle(rsKindColor(bubble.kind))

            Text(bubble.text)
                .font(.rsSerif(19, .regular))
                .foregroundStyle(Color.rsInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rsKindColor(bubble.kind).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(rsKindColor(bubble.kind).opacity(0.25), lineWidth: 1)
        )
    }

    private func stopAutoGlance() {
        autoTask?.cancel()
        autoTask = nil
    }

    private func performGlance() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        guard
            let image = await glasses.capturePhoto(),
            let jpeg = image.jpegData(compressionQuality: 0.6)
        else {
            bubbles.append(
                WhisperBubble(
                    text: "I couldn't take a photo just now — check the camera settings in Connect.",
                    kind: "info", matched: ""
                )
            )
            return
        }
        withAnimation { lastCapture = image }

        do {
            let result = try await ReminiAPI.glance(jpeg: jpeg)
            guard !result.whisper.text.isEmpty else { return }
            bubbles.append(
                WhisperBubble(
                    text: result.whisper.text,
                    kind: result.whisper.kind,
                    matched: result.matched
                )
            )
            // Ear: TTS through the glasses speakers when they're routed.
            speech.speak(result.whisper.text)
            // Lens: the card on the glasses display.
            Task {
                await ReminiCards.shared.show(
                    text: result.whisper.text,
                    kind: result.whisper.kind,
                    matched: result.matched
                )
            }
        } catch {
            bubbles.append(
                WhisperBubble(
                    text: "Couldn't reach ReminiSense: \(error.localizedDescription)",
                    kind: "info", matched: ""
                )
            )
        }
    }
}
