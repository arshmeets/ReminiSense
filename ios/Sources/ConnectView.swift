import SwiftUI
import UIKit

/// Hardware + backend setup. Glasses are optional everywhere in Recall —
/// the iPhone camera is a first-class capture source, not a degraded mode.
struct ConnectView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @ObservedObject private var cards = ReminiCards.shared
    @ObservedObject private var dictation = DictationManager.shared
    @ObservedObject private var audio = AudioSessionController.shared
    @AppStorage("reminiUsePhoneCamera") private var usePhoneCamera = false
    @AppStorage("recallBaseURL") private var baseURL = RecallAPI.defaultBase
    @State private var backendStatus: String?
    @State private var checkingBackend = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    lensCard
                    audioCard
                    cameraCard
                    backendCard
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { glasses.refreshCameraAuth() }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        glasses.isConnected
                            ? Color.rcAccent.opacity(0.18)
                            : Color.rcSurfaceHi
                    )
                    .overlay(
                        Circle().stroke(
                            glasses.isConnected ? Color.rcAccent : Color.rcLine,
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 84, height: 84)
                Image(systemName: "eyeglasses")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        glasses.isConnected ? Color.rcAccent : Color.rcTextDim
                    )
            }
            .animation(.easeInOut(duration: 0.35), value: glasses.isConnected)

            Text(glasses.isConnected ? "Glasses connected" : "Glasses not connected")
                .font(.rcDisplay(22))
                .foregroundStyle(Color.rcText)

            Text(glasses.statusText)
                .font(.rcCaption)
                .foregroundStyle(Color.rcTextDim)
                .multilineTextAlignment(.center)

            if glasses.displayReady {
                Label("Lens display ready", systemImage: "sparkles")
                    .font(.rcCaption.weight(.medium))
                    .foregroundStyle(Color.rcAccent)
            }

            Button {
                glasses.toggleConnection()
            } label: {
                Text(glasses.isConnected ? "Disconnect" : "Connect glasses")
            }
            .buttonStyle(AccentButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.rcSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.rcLine, lineWidth: 1)
        )
    }

    /// Answers "why is nothing on the lens?" without guessing.
    private var lensCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Lens", icon: "eyeglasses")
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(cards.connected ? Color.rcAccent : Color.rcTextDim)
                        .frame(width: 7, height: 7)
                    Text(cards.connected ? "connected" : "idle")
                        .font(.rcLabel)
                        .foregroundStyle(
                            cards.connected ? Color.rcAccent : Color.rcTextDim
                        )
                }
            }

            Text(cards.lensStatus)
                .font(.rcCaption)
                .foregroundStyle(cards.lastSendFailed ? Color.rcAlert : Color.rcText)
                .fixedSize(horizontal: false, vertical: true)

            if !cards.connected {
                Text("Cards will not reach the glasses until the display session reports `.started`. Everything else — recognition, auto-enroll, the spoken line and the in-app card — keeps working without it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rcTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await ReminiCards.shared.showNote("Recall test card — the lens is live.") }
                } label: {
                    Label("Send a test card", systemImage: "paperplane.fill")
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAccent))

                Button {
                    Task { await ReminiCards.shared.clear() }
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(GhostButtonStyle(tint: .rcTextDim))
            }

            if !glasses.displayLog.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(glasses.displayLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.rcTextDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                } label: {
                    Text("Display session log (\(glasses.displayLog.count))")
                        .font(.rcLabel)
                        .foregroundStyle(Color.rcTextDim)
                }
                .tint(.rcTextDim)
            }
        }
        .panel()
    }

    /// Microphone + speech-recognition truth, so a denied permission is never
    /// a silent failure.
    private var audioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Mic & transcription", icon: "waveform")
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(dictation.isUsable ? Color.rcAccent : Color.rcAlert)
                        .frame(width: 7, height: 7)
                    Text(dictation.isUsable ? "ready" : "blocked")
                        .font(.rcLabel)
                        .foregroundStyle(
                            dictation.isUsable ? Color.rcAccent : Color.rcAlert
                        )
                }
            }

            Text(dictation.authSummary)
                .font(.rcCaption)
                .foregroundStyle(dictation.isUsable ? Color.rcText : Color.rcAlert)
                .fixedSize(horizontal: false, vertical: true)

            Text(dictation.diagnostic)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.rcTextDim)
                .fixedSize(horizontal: false, vertical: true)

            Text(audio.status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(audio.isActive ? Color.rcTextDim : Color.rcAlert)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await DictationManager.shared.requestAuthorization()
                        AudioSessionController.shared.reassert()
                        DictationManager.shared.prime()
                    }
                } label: {
                    Label("Re-check mic", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAccent))

                if !dictation.isUsable {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(GhostButtonStyle(tint: .rcAlert))
                }
            }
        }
        .panel()
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Camera", icon: "camera.fill")
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(glasses.cameraBlocked ? Color.rcAlert : Color.rcAccent)
                        .frame(width: 7, height: 7)
                    Text(glasses.cameraBlocked ? "blocked" : "ready")
                        .font(.rcLabel)
                        .foregroundStyle(
                            glasses.cameraBlocked ? Color.rcAlert : Color.rcAccent
                        )
                }
            }

            Text(glasses.cameraAuthSummary)
                .font(.rcCaption)
                .foregroundStyle(glasses.cameraBlocked ? Color.rcAlert : Color.rcText)
                .fixedSize(horizontal: false, vertical: true)

            if glasses.cameraBlocked {
                Text("iOS is refusing the camera, so Meet will hear the conversation and save it, but can't match or add a face.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rcTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAlert))
            }

            if !glasses.lastFrameSource.isEmpty {
                Text("Last frame came from the \(glasses.lastFrameSource).")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.rcTextDim)
            }

            Divider().overlay(Color.rcLine)

            Toggle(isOn: $usePhoneCamera) {
                Label("Force the iPhone camera", systemImage: "iphone")
                    .font(.rcBodyMedium)
                    .foregroundStyle(Color.rcText)
            }
            .tint(.rcAccent)

            Text(
                usePhoneCamera
                    ? "Capture always uses the phone's rear camera — the whole demo runs without glasses."
                    : "Capture uses the glasses camera when they're connected and falls back to the phone the moment they aren't."
            )
            .font(.rcCaption)
            .foregroundStyle(Color.rcTextDim)
        }
        .panel()
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Graph backend", icon: "point.3.filled.connected.trianglepath.dotted")

            TextField(
                "", text: $baseURL,
                prompt: Text(RecallAPI.defaultBase).foregroundColor(Color.rcTextDim)
            )
            .font(.rcMono)
            .foregroundStyle(Color.rcText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .padding(12)
            .background(Color.rcSurfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    Task { await checkBackend() }
                } label: {
                    if checkingBackend {
                        ProgressView().controlSize(.small).tint(.rcAccent)
                    } else {
                        Label("Test connection", systemImage: "bolt.horizontal")
                    }
                }
                .buttonStyle(GhostButtonStyle(tint: .rcAccent))

                Button("Reset to default") {
                    baseURL = RecallAPI.defaultBase
                    backendStatus = nil
                }
                .buttonStyle(GhostButtonStyle(tint: .rcTextDim))
            }

            if let backendStatus {
                Text(backendStatus)
                    .font(.rcCaption)
                    .foregroundStyle(
                        backendStatus.hasPrefix("Connected")
                            ? Color.rcAccent : Color.rcAlert
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panel()
    }

    private func checkBackend() async {
        checkingBackend = true
        defer { checkingBackend = false }
        do {
            let people = try await RecallAPI.roster()
            backendStatus = "Connected — \(people.count) people in the graph."
        } catch {
            backendStatus = "Unreachable — \(error.localizedDescription)"
        }
    }
}
