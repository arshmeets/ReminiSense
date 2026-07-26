# ReminiSense on Meta Ray-Ban Display — integration guide

Everything below is adapted from Meta's official `DisplayAccess` sample
(meta-wearables-dat-ios **0.8.0**, Display capability shipped in 0.7, May 2026).
The app runs on the paired iPhone; the glasses are camera-in / lens-out /
Neural-Band-select. Camera + Display are confirmed to work **in the same
DeviceSession** (Meta staff, dat-ios discussion #193).

## 0. Project setup (Xcode)

- SPM package: `https://github.com/facebook/meta-wearables-dat-ios`,
  **exact 0.8.0**; add products **MWDATCore, MWDATDisplay, MWDATCamera**
- `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
- Info.plist (crib from cascade-thcc, add the URL scheme + MWDAT block):

```xml
<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key><string>reminisense://</string>
  <key>MetaAppID</key><string>0</string>            <!-- "0" is fine in Developer Mode -->
  <key>ClientToken</key><string>$(CLIENT_TOKEN)</string>
  <key>TeamID</key><string>$(DEVELOPMENT_TEAM)</string>
</dict>
```

Plus `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`,
`NSBonjourServices` (`_bonjour._tcp`), `UIBackgroundModes` (processing,
bluetooth-central, bluetooth-peripheral), `fb-viewapp` in
`LSApplicationQueriesSchemes`. Do NOT set `MWDAT.DAMEnabled=false` anywhere —
DAM (required for Display) defaults to true on 0.8.

Glasses side: Meta AI app → Settings → Your glasses → **Developer Mode ON**.

## 1. One session, both capabilities

```swift
import MWDATCore
import MWDATCamera
import MWDATDisplay

let wearables = Wearables.shared   // Wearables.configure() in App.init, as in Cascade

let selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
let session = try wearables.createSession(deviceSelector: selector)
try session.start()
for await state in session.stateStream() { if state == .started { break } }

// camera (frames in)
let stream = session.addStream(config: StreamConfiguration(
    videoCodec: .raw, resolution: .medium, frameRate: 15))

// display (cards out)
let display = try session.addDisplay()
let token = display.statePublisher.listen { state in
    if state == .started { ReminiCards.shared.ready = true }
}
display.start()   // synchronous on 0.8
```

Gotcha: keep `token` alive; wait for `DisplayState.started` before sending;
in files that import SwiftUI, qualify `MWDATDisplay.Text` etc. (Meta keeps
display builders in non-SwiftUI files — do the same).

## 2. The glance loop (deliberate capture, not recording)

```swift
// on temple tap / app button:
stream.capturePhoto(format: .jpeg)
let photoToken = stream.photoDataPublisher.listen { photo in
    Task { await ReminiSenseAPI.glance(jpeg: photo.data) }
}

enum ReminiSenseAPI {
    static var base = URL(string: "http://<MAC-LAN-IP>:8000")!   // or the sandbox URL

    static func glance(jpeg: Data) async {
        var req = URLRequest(url: base.appending(path: "/walker/glance"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject:
            ["image_b64": jpeg.base64EncodedString(), "source": "glasses"])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = ((json["data"] as? [String: Any])?["reports"] as? [[String: Any]])?.first,
              let whisper = payload["whisper"] as? [String: Any] else { return }
        await ReminiCards.shared.show(
            text: whisper["text"] as? String ?? "",
            kind: whisper["kind"] as? String ?? "reassurance",
            matched: payload["matched"] as? String ?? "")
    }
}
```

## 3. Rendering the lens cards

`display.send(_:)` takes ONE root view and replaces the whole screen (and its
tap handlers). Neural Band pinch arrives as `Button(onClick:)` / `.onTap`.

```swift
import MWDATDisplay

final class ReminiCards {
    static let shared = ReminiCards()
    var ready = false
    var display: Display!

    // recognition: MAYA / your daughter / one hook + "more" pager
    func show(text: String, kind: String, matched: String) async {
        guard ready else { return }
        switch kind {
        case "recognition":
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text(matched.uppercased(), style: .heading)
                    Text(text, style: .body, wrap: true)
                    Button(label: "more", style: .primary, iconName: .triangleRightVerticalLine,
                           onClick: { Task { await self.showAskAbout(name: matched, page: 0) } })
                }.padding(24).background(.card)
            )
        case "warning":   // double dose — holds until dismissed
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text("WAIT", style: .heading)
                    Text(text, style: .body, wrap: true)
                    Button(label: "OK", style: .primary, iconName: .checkmark,
                           onClick: { Task { try? await self.display.clearDisplay() } })
                }.padding(24).background(.card)
            )
        default:          // reassurance / object
            try? await display.send(
                FlexBox(direction: .column, spacing: 12) {
                    Text(text, style: .body, wrap: true)
                }.padding(24).background(.card)
            )
            try? await Task.sleep(for: .seconds(8))
            try? await display.clearDisplay()
        }
    }

    // "more" = the Connection Card MD, distilled: page through "Things to ask about"
    func showAskAbout(name: String, page: Int) async {
        let bullets = await ReminiSenseAPI.askAboutBullets(name: name)  // parses '- ' lines
        guard !bullets.isEmpty else { return }                          // under '## Things to ask about'
        let i = page % bullets.count                                    // from /walker/person_card md
        try? await display.send(
            FlexBox(direction: .column, spacing: 12) {
                Text("ask \(name) about…", style: .meta, color: .secondary)
                Text(bullets[i], style: .body, wrap: true)
                Button(label: "next", style: .primary, iconName: .triangleRightVerticalLine,
                       onClick: { Task { await self.showAskAbout(name: name, page: i + 1) } })
            }.padding(24).background(.card)
        )
    }
}
```

Teardown: `display.stop(); session.stop()`, cancel listener tokens.

## 4. Demo insurance

- Phone-camera fallback: reuse `PhoneCameraFallback.swift` from cascade-thcc —
  same `glance` POST, no glasses needed.
- No camera at all: the dashboard's 4 demo buttons hit `glance_cached`, which
  runs the identical downstream pipeline.
- TTS through the glasses speakers (Cascade's `SpeechManager`) mirrors every
  card for eyes-free use — keep it on.

## References

Meta DisplayAccess sample: samples/DisplayAccess in facebook/meta-wearables-dat-ios ·
display-access SKILL.md in plugins/mwdat-ios/skills · dat-ios discussion #193
(camera+display coexistence) · CHANGELOG 0.7.0/0.8.0.
