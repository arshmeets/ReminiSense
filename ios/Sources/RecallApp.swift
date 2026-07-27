import MWDATCore
import SwiftUI

/// Surfaces the DAT bootstrap error in the UI instead of swallowing it.
enum DATBootstrap {
    nonisolated(unsafe) static var error: String?
}

@main
struct RecallApp: App {
    @StateObject private var glasses = GlassesManager()
    @StateObject private var speech = SpeechManager()

    init() {
        do {
            try Wearables.configure()
        } catch {
            DATBootstrap.error = "\(error)"
            print("Wearables.configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(glasses)
                .environmentObject(speech)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Return leg of DAT registration via our URL scheme.
                    guard
                        let components = URLComponents(
                            url: url, resolvingAgainstBaseURL: false
                        ),
                        components.queryItems?.contains(where: {
                            $0.name == "metaWearablesAction"
                        }) == true
                    else { return }
                    Task { _ = try? await Wearables.shared.handleUrl(url) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @EnvironmentObject private var speech: SpeechManager
    @State private var tab: Int = 0  // land on Meet — the one-tap demo
    @State private var bootstrapped = false

    var body: some View {
        TabView(selection: $tab) {
            MeetView()
                .tabItem { Label("Meet", systemImage: "sparkles") }
                .tag(0)
            ManualView()
                .tabItem { Label("Manual", systemImage: "slider.horizontal.3") }
                .tag(1)
            NetworkView()
                .tabItem { Label("Network", systemImage: "person.2.fill") }
                .tag(2)
            ConnectView()
                .tabItem { Label("Connect", systemImage: "eyeglasses") }
                .tag(3)
            GuideView()
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag(4)
        }
        .tint(Color.rcAccent)
        .task {
            guard !bootstrapped else { return }
            bootstrapped = true
            glasses.configure()

            // Audio session first, then permissions, then the mic engine.
            // Doing this at launch means a denied permission shows up in the UI
            // now, not the first time the button is pressed on stage.
            AudioSessionController.shared.activate()
            await DictationManager.shared.requestAuthorization()
            DictationManager.shared.prime()
            MeetEngine.shared.bind(glasses: glasses, speech: speech)
        }
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.rcInk)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

/// The manual fallbacks, kept intact behind one tab: single-shot Capture and
/// press-and-hold Listen. Meet does both at once; these exist for when a demo
/// needs to isolate one half.
struct ManualView: View {
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Capture").tag(0)
                Text("Listen").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if mode == 0 {
                CaptureView()
            } else {
                ListenView()
            }
        }
        .background(Color.rcInk.ignoresSafeArea())
    }
}
