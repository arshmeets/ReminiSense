# ReminiSense

Ambient recall for the things you're supposed to remember about people.

You look at someone. A frame goes from the phone to a Jac backend on a laptop.
The backend works out who they are, walks a knowledge graph for the context
that matters, and sends back one short line — which the phone whispers into a
Bluetooth earpiece.

> *"Sarah Chen, VP Product at Acme — you discussed Series B, there's an open pricing question."*

Built at JacHacks SF.

---

## Architecture

```
iPhone (SwiftUI)                 MacBook (Jac)
┌──────────────────┐             ┌─────────────────────────────────────┐
│ AVFoundation     │  512px JPEG │  Recognize walker                   │
│  capture ────────┼─ base64 ───▶│    ├─ embed_face()   SFace, ~20ms   │
│                  │   HTTP POST │    ├─ visit [-->]    score people   │
│ AVSpeechSynth ◀──┼─ spoken ────┤    ├─ compose()      by llm()       │
│  → Bluetooth     │    line     │    └─ append Encounter              │
└──────────────────┘             └─────────────────────────────────────┘
```

**Identity is not an LLM call.** Face matching runs locally through OpenCV's
YuNet detector and SFace recogniser — a 128-d embedding compared by cosine
distance. Measured on this hardware:

| Step | Approach | Latency |
|---|---|---|
| Face identity | SFace embedding, local | **31ms** |
| Face identity | multimodal LLM | 1,260ms |
| Spoken line | `by llm()` over graph context | ~1,300ms |

An all-LLM pipeline spends ~2.6s in the model before capture, network, or
speech — over budget for something meant to feel ambient. It can also *refuse*:
models are trained to decline naming a person from a photo, which is a bad
thing to discover in front of an audience. Embeddings are deterministic, offline
(no dependency on conference WiFi), and 40× faster.

So `by llm()` is pointed where language is the actual problem: turning retrieved
graph context into something worth whispering.

---

## How Jac is used

**`node`** — `Person`, `Thing`, `Encounter`. `Person` carries its own face
embedding, so identity lives on the graph rather than in a sidecar index.

**`edge`** — typed, with attributes that carry weight:

```jac
edge Knows: Root --> Person {
    has closeness: float = 0.5,
        recency: float = 0.5;
}
```

Those attributes aren't decoration — `Recognize` reads them mid-traversal and
lets the relationship bias the match, so someone you know well and saw recently
resolves more readily than a faint acquaintance:

```jac
links = [edge here <-:Knows:<-];
if len(links) > 0 {
    weight = 1.0 + (0.15 * links[0].closeness) + (0.10 * links[0].recency);
}
```

**`walker`** — `Recognize` enters at root, embeds the frame once, visits every
`Person`, scores each, and composes on the way out. It reports the traversal
path alongside the line, so the graph's work is visible rather than implied.

**`by llm()`** — Meaning-Typed Programming, no prompt strings. The signature and
`sem` statements *are* the prompt:

```jac
def compose(name: str, role: str, org: str, relationship: str,
            last: str, notes: str, history: str) -> Spoken by fast(temperature=0.3);
sem compose      = "Write one short line to be whispered into the wearer's earpiece...";
sem compose.last = "What happened at the last interaction.";
```

`Encounter` nodes are appended on every recognition, so context compounds as the
demo runs — the second time you see someone, the graph knows about the first.

---

## Running it

Requires `jac 0.34.7` and an Anthropic API key.

```bash
cd backend
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .env     # gitignored
jac install                                     # syncs byLLM + opencv into .jac/venv
set -a; source .env; set +a                     # jac does NOT auto-read .env
jac start app.jac --no-client --port 8000
```

The server prints its LAN address on boot. **Use that address in the iOS app** —
it changes between networks, which is why the host is a field in the UI and not
a constant in the source.

### Testing without the phone

`demo.sh` wraps the endpoints and does the same 512px downscale the app does:

```bash
./demo.sh reset                              # wipe + reseed the demo graph
./demo.sh enroll "Sarah Chen" sarah.jpg      # enrol a face
./demo.sh look frame.jpg                     # recognise, print the spoken line
./demo.sh roster                             # show the graph
```

Raw `curl`, if you'd rather:

```bash
# recognise a frame
B64=$(python3 -c "import base64;print(base64.b64encode(open('frame.jpg','rb').read()).decode())")
curl -s -X POST http://127.0.0.1:8000/walker/Recognize \
     -H 'Content-Type: application/json' \
     -d "{\"frame_b64\":\"$B64\"}" | python3 -m json.tool

# rebuild the demo graph (two calls, on purpose - see below)
curl -s -X POST http://127.0.0.1:8000/walker/Reset -H 'Content-Type: application/json' -d '{}'
curl -s -X POST http://127.0.0.1:8000/walker/Seed  -H 'Content-Type: application/json' -d '{}'
```

Swagger is at `http://127.0.0.1:8000/docs`.

### Endpoints

| Walker | Does |
|---|---|
| `Recognize` | Identify who's in frame, return the spoken line + traversal path |
| `Enroll` | Add a person from a reference photo (live, on stage) |
| `Reset` / `Seed` | Rebuild the demo graph |
| `Roster` | Dump the graph — used by the dashboard |

---

## Things worth knowing

**Reset and Seed are two calls, deliberately.** Deletions land at commit time,
so wiping and re-seeding inside one walker destroys the nodes it just created.
Found the hard way.

**Backlit frames need equalising first.** Wearable capture is close-range and
usually backlit, which drops the face into shadow and hides it from the
detector. Equalising the luminance channel (CLAHE) before detection is the
difference between needing a desperate 0.15 score threshold and a comfortable
0.5. On a genuinely hard backlit frame, two separate captures of the same person
matched at **0.84 cosine** against a 0.363 same-identity threshold.

**No confident match means silence.** Below threshold, `spoken` comes back empty
and the phone says nothing. A wrong name whispered with confidence is worse than
no name at all.

**The whisper never guesses pronouns.** Pronouns aren't a field on `Person`, so
`compose` is instructed to use the person's name or "they" and never infer from
a name or a face. Getting that wrong in a tool built for remembering people is
its own kind of failure.

**Walker `has` fields are the request body.** Internal traversal state has to be
JSON-safe — a `Person | None` field makes the endpoint return 422. `Recognize`
tracks its best match as a `jid` string and resolves the node at the end.
