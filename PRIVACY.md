# ReminiSense Privacy Guardrails

ReminiSense handles the most intimate data imaginable — a person's memory.
These guardrails are engineered in, not policy promises.

## 1. Biometrics stay home, and only with consent
Face embeddings (128 floats, SFace) are computed **only at deliberate
enrollment by a family member** and live exclusively inside that user's
private graph — they are never sent to any cloud model (matching is local
cosine similarity), never shared, and `forget` deletes them with the person.
Strangers are never embedded: an unrecognized face produces a generic whisper
and stores nothing. A second tier of plain-language descriptive notes means
families can also opt out of embeddings entirely and still get recognition.

## 2. Frames are ephemeral
Camera frames are processed in memory, written only to a temp file for the
vision call, and **deleted immediately after** (`vision.cleanup()` runs on
every path, including errors). No image is ever persisted to the graph,
logs, or disk.

## 3. The memory graph is private by architecture
Everything hangs off a per-user `root` node — Jac's persistence model gives
every account an **isolated private graph**. Eleanor's memories live in
Eleanor's node. There is no cross-user query surface.

## 4. Consent-based enrollment
People appear in the graph only when a family member enrolls them
deliberately. ReminiSense never auto-enrolls strangers: an unrecognized
face produces a gentle generic whisper and **stores nothing**.

## 5. The right to be forgotten is a first-class walker
`POST /walker/forget {"name": "..."}` deletes a person, their encounters,
their Connection Card, and all references — walked and removed from the
graph in one call. Demonstrable on demand.

## 6. Whispers never shame, never diagnose
Tone rules live in `sem` annotations: never mention the diagnosis, never
say "you forgot." The safety-critical path (double-dose prevention) is
**deterministic graph logic — no LLM in the loop** — so medication
decisions are auditable line by line.

## 7. Persona filter — summaries only, at write time
Every encounter passes through a sanitization layer BEFORE it touches the
graph: a typed `sanitize_summary` LLM filter (with a deterministic regex
fallback) strips third-party medical details, finances, credentials,
addresses, and anything embarrassing. Only a warm neutral summary is
stored — raw conversation content never enters the memory graph, so it
can never leak from it.

## 8. Caregiver transparency, not surveillance
Maya sees a daily digest letter and medication adherence — not a camera
feed, not a location trail, not raw transcripts. Alerts fire only for
safety events (a prevented double dose).
