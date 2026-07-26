# Recall — brand usage

Wordmark: `rec` ghosted + `all` full weight. Typeface **Poppins** (Medium/SemiBold
for `all`, same weight ghosted for `rec`). Accent: periwinkle **#7B68EE**-family
dot on the app icon.

| Variant | Ghost | Use |
|---|---|---|
| Primary | 20% | repo, Devpost, README, print (light bg) |
| Hardware | 45% | glasses display, projector, bright rooms |
| Flat | none | embroidery, stickers, single-colour |
| **Reversed** | 30% | **dark UI, stage slides, demo video** |

App icon: lowercase `r` on a rounded-square dark tile with the accent dot at the
top-right. Wordmark alone gives nothing square — the icon is its partner.

Minimum size: wordmark 72px on screen / 18mm print; icon 24px. Below that the
ghost disappears — use the flat variant.

Clear space: height of the `r` on all sides.

Implementation note: reproduce in live text (CSS/SwiftUI) rather than bitmaps so
it stays crisp — e.g. `<span class="ghost">rec</span><span class="solid">all</span>`
with the ghost at the variant's opacity.
