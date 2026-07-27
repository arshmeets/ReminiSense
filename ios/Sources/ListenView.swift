import SwiftUI

/// THE demo. Hold the button while someone introduces themselves; the live
/// transcript builds on screen, and on release it goes to /walker/ingest —
/// the graph learns a new person, their company, what you talked about, and
/// what you owe them.
struct ListenView: View {
    /// Shared on purpose: the audio engine and its input tap are process-wide,
    /// so every screen drives the same manager rather than fighting over the
    /// input node.
    @ObservedObject private var dictation = DictationManager.shared
    @State private var receipts: [IngestReceipt] = []
    @State private var sending = false
    @State private var errorText: String?
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    micButton
                        .padding(.top, 8)

                    Text(hint)
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcTextDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    transcriptPanel

                    if !dictation.transcript.isEmpty && !dictation.isRecording {
                        HStack(spacing: 10) {
                            Button {
                                Task { await submit() }
                            } label: {
                                if sending {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Save to graph", systemImage: "arrow.up.circle.fill")
                                }
                            }
                            .buttonStyle(AccentButtonStyle())
                            .disabled(sending)

                            Button {
                                dictation.reset()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(GhostButtonStyle(tint: .rcTextDim))
                        }
                    }

                    if let errorText = errorText ?? dictation.errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcAlert)
                            .panel()
                    }

                    receiptsList
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Listen")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft = dictation.transcript
                        editing = true
                    } label: {
                        Image(systemName: "keyboard")
                            .foregroundStyle(Color.rcTextDim)
                    }
                }
            }
            .sheet(isPresented: $editing) {
                typeSheet
            }
        }
        .onDisappear {
            if dictation.isRecording { _ = dictation.stop() }
        }
    }

    private var hint: String {
        if dictation.isRecording {
            return "Listening — let them talk. Release when they're done."
        }
        if dictation.transcript.isEmpty {
            return "Hold while someone introduces themselves. Recall pulls out who they are, where they work, what you discussed, and what you promised."
        }
        return "Send it to the graph, or hold again to add more."
    }

    private var micButton: some View {
        ZStack {
            Circle()
                .fill(Color.rcAccent.opacity(0.15))
                .frame(width: 190, height: 190)
                .scaleEffect(dictation.isRecording ? 1 + dictation.level * 0.35 : 0.8)
                .opacity(dictation.isRecording ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: dictation.level)

            Circle()
                .fill(dictation.isRecording ? Color.rcAccent : Color.rcSurface)
                .overlay(
                    Circle().stroke(
                        dictation.isRecording ? Color.clear : Color.rcAccent,
                        lineWidth: 1.5
                    )
                )
                .frame(width: 150, height: 150)
                .shadow(
                    color: Color.rcAccent.opacity(dictation.isRecording ? 0.5 : 0.15),
                    radius: 24, y: 8
                )

            VStack(spacing: 6) {
                Image(systemName: dictation.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .medium))
                Text(dictation.isRecording ? "Listening" : "Hold to listen")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(dictation.isRecording ? Color.white : Color.rcAccent)
        }
        .frame(height: 200)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !dictation.isRecording, !sending else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await dictation.start() }
                }
                .onEnded { _ in
                    guard dictation.isRecording else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    _ = dictation.stop()
                }
        )
        .accessibilityLabel("Hold to listen and transcribe the conversation")
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Transcript", icon: "text.quote")
                Spacer()
                if dictation.isRecording {
                    HStack(spacing: 5) {
                        Circle().fill(Color.rcAlert).frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.rcLabel)
                            .foregroundStyle(Color.rcAlert)
                    }
                }
            }
            Text(
                dictation.transcript.isEmpty
                    ? "Nothing captured yet."
                    : dictation.transcript
            )
            .font(.system(size: 17))
            .foregroundStyle(
                dictation.transcript.isEmpty ? Color.rcTextDim : Color.rcText
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .animation(.easeOut(duration: 0.2), value: dictation.transcript)

            // Always-visible proof the pipeline is alive (or a reason it isn't).
            Text(dictation.diagnostic)
                .font(.system(size: 11))
                .foregroundStyle(Color.rcTextDim.opacity(0.8))
            if !dictation.isUsable {
                Text(dictation.authSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.rcAlert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panel()
    }

    private var receiptsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !receipts.isEmpty {
                SectionLabel("What the graph learned", icon: "point.3.connected.trianglepath.dotted")
                ForEach(receipts.reversed()) { receipt in
                    ReceiptCardView(receipt: receipt)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.45), value: receipts.count)
    }

    private var typeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type or paste what was said — same pipeline, no microphone.")
                    .font(.rcCaption)
                    .foregroundStyle(Color.rcTextDim)
                TextEditor(text: $draft)
                    .font(.rcBody)
                    .foregroundStyle(Color.rcText)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.rcSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(minHeight: 180)
                Spacer()
            }
            .padding(20)
            .recallScreen()
            .navigationTitle("Type it out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editing = false }
                        .tint(.rcTextDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        dictation.setTranscript(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        editing = false
                    }
                    .tint(.rcAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Flow

    private func submit() async {
        let text = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        errorText = nil
        defer { sending = false }

        do {
            let receipt = try await RecallAPI.ingest(transcript: text)
            receipts.append(receipt)
            dictation.reset()
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            let name = receipt.saved
            if !name.isEmpty {
                let note = receipt.newPerson
                    ? "\(name) added to your network"
                    : "\(name) updated"
                Task { await ReminiCards.shared.showNote(note) }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Ingest receipt

struct ReceiptCardView: View {
    let receipt: IngestReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.saved.isEmpty ? "Saved" : receipt.saved)
                        .font(.rcDisplay(22))
                        .foregroundStyle(Color.rcText)
                    if !receipt.org.isEmpty {
                        Text(receipt.org)
                            .font(.rcCaption.weight(.medium))
                            .foregroundStyle(Color.rcAccent)
                    }
                }
                Spacer()
                Chip(
                    text: receipt.newPerson ? "NEW" : "UPDATED",
                    tint: receipt.newPerson ? .rcAccent : .rcTextDim,
                    filled: receipt.newPerson
                )
            }

            if !receipt.topics.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("Topics")
                    FlowChips(items: receipt.topics)
                }
            }

            if !receipt.newTopics.isEmpty {
                Text("New to your graph: \(receipt.newTopics.joined(separator: ", "))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.rcTextDim)
            }

            if !receipt.followups.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("Follow-ups", icon: "checklist")
                    ForEach(Array(receipt.followups.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "square")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.rcAccent)
                            Text(item)
                                .font(.rcBody)
                                .foregroundStyle(Color.rcText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text(receipt.date, style: .time)
                .font(.system(size: 12))
                .foregroundStyle(Color.rcTextDim)
        }
        .panel()
    }
}
