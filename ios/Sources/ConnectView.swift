import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @AppStorage("reminiUsePhoneCamera") private var usePhoneCamera = false
    @AppStorage("reminiBaseURL") private var baseURL = ReminiAPI.defaultBase
    @State private var backendStatus: String?
    @State private var checkingBackend = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    cameraCard
                    settingsCard
                }
                .padding(20)
            }
            .background(Color.rsCream.ignoresSafeArea())
            .navigationTitle("Connect")
        }
    }

    private var statusCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: glasses.isConnected
                                ? [.rsSage, .rsSage.opacity(0.7)]
                                : [.rsAmber.opacity(0.5), .rsTerracotta.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                Image(systemName: "eyeglasses")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .animation(.easeInOut(duration: 0.4), value: glasses.isConnected)

            Text(glasses.isConnected ? "Glasses connected" : "Glasses not connected")
                .font(.rsSerif(26))
                .foregroundStyle(Color.rsInk)

            Text(glasses.statusText)
                .font(.rsCaption)
                .foregroundStyle(Color.rsInkSoft)
                .multilineTextAlignment(.center)

            if glasses.displayReady {
                Label("Lens display ready", systemImage: "sparkles")
                    .font(.rsCaption.weight(.medium))
                    .foregroundStyle(Color.rsSage)
            }

            Button {
                glasses.toggleConnection()
            } label: {
                Text(glasses.isConnected ? "Disconnect" : "Connect glasses")
                    .font(.rsBodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(glasses.isConnected ? Color.rsInkSoft : Color.rsTerracotta)
            .clipShape(Capsule())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.rsCard)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.rsInk.opacity(0.06), radius: 10, y: 4)
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $usePhoneCamera) {
                Label("Use iPhone camera", systemImage: "iphone")
                    .font(.rsBodyMedium)
                    .foregroundStyle(Color.rsInk)
            }
            .tint(.rsTerracotta)

            Text(
                usePhoneCamera
                    ? "Glances will use the phone's rear camera — perfect for demos without glasses."
                    : "Glances use the glasses camera when connected, and quietly fall back to the phone when not."
            )
            .font(.rsCaption)
            .foregroundStyle(Color.rsInkSoft)
        }
        .softCard()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Care backend")
                .font(.rsSerif(20))
                .foregroundStyle(Color.rsInk)

            TextField("Backend URL", text: $baseURL)
                .font(.system(size: 16, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color.rsCream)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    Task { await checkBackend() }
                } label: {
                    if checkingBackend {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test connection")
                            .font(.rsCaption.weight(.medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.rsTerracotta)

                if let backendStatus {
                    Text(backendStatus)
                        .font(.rsCaption)
                        .foregroundStyle(
                            backendStatus.hasPrefix("Connected")
                                ? Color.rsSage : Color.rsWarn
                        )
                }
            }
        }
        .softCard()
    }

    private func checkBackend() async {
        checkingBackend = true
        defer { checkingBackend = false }
        do {
            _ = try await ReminiAPI.timeline()
            backendStatus = "Connected"
        } catch {
            backendStatus = "Unreachable — \(error.localizedDescription)"
        }
    }
}
