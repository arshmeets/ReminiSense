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
    @State private var tab: Int = 2  // land on Listen — the demo

    var body: some View {
        TabView(selection: $tab) {
            ConnectView()
                .tabItem { Label("Connect", systemImage: "eyeglasses") }
                .tag(0)
            CaptureView()
                .tabItem { Label("Capture", systemImage: "viewfinder") }
                .tag(1)
            ListenView()
                .tabItem { Label("Listen", systemImage: "mic.fill") }
                .tag(2)
            NetworkView()
                .tabItem { Label("Network", systemImage: "person.2.fill") }
                .tag(3)
            GuideView()
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag(4)
        }
        .tint(Color.rcAccent)
        .onAppear {
            glasses.configure()
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.rcInk)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
