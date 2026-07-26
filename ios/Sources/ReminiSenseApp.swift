import MWDATCore
import SwiftUI

/// Surfaces the DAT bootstrap error in the UI instead of swallowing it.
enum DATBootstrap {
    nonisolated(unsafe) static var error: String?
}

@main
struct ReminiSenseApp: App {
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
    @State private var tab: Int = 1  // land on Glance — the demo

    var body: some View {
        TabView(selection: $tab) {
            ConnectView()
                .tabItem { Label("Connect", systemImage: "eyeglasses") }
                .tag(0)
            GlanceView()
                .tabItem { Label("Glance", systemImage: "eye.fill") }
                .tag(1)
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2.fill") }
                .tag(2)
            GuideView()
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag(3)
        }
        .tint(Color.rsTerracotta)
        .onAppear { glasses.configure() }
    }
}
