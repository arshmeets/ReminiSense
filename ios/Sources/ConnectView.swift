import SwiftUI

/// Hardware + backend setup. Glasses are optional everywhere in Recall —
/// the iPhone camera is a first-class capture source, not a degraded mode.
struct ConnectView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @AppStorage("reminiUsePhoneCamera") private var usePhoneCamera = false
    @AppStorage("recallBaseURL") private var baseURL = RecallAPI.defaultBase
    @State private var backendStatus: String?
    @State private var checkingBackend = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    cameraCard
                    backendCard
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.large)
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

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
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
