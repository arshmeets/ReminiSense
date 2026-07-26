# ReminiSense — Devpost submission draft

**Track:** Social Impact (also relevant: Agentic AI)
**Tagline:** A memory that stays — ambient recall for people living with early-stage Alzheimer's.

## Inspiration

55 million people live with dementia. The cruelty isn't only forgetting — it's
the moment a familiar face arrives and nothing comes. The daughter waits for
recognition that doesn't land. Existing tools are reminder apps: they assume you
remember to check them.

## What it does

Eleanor wears Meta Ray-Ban Display glasses. She looks at someone and taps.

- **A card appears in her lens** and a whisper in her ear: *"That's Maya, your
  daughter. She just moved to San Francisco — ask about her new apartment."*
- **The graph grows.** That encounter is written into her memory graph, so the
  next time Maya appears the whisper says *"You saw her this morning — you
  talked about her apartment."*
- **Connection Cards**: every person has a living markdown dossier — who they
  are, your story together, three things to ask about — rendered from the graph
  and regenerated after every visit.
- **Medication safety**: look at a pill bottle. If today's dose is already
  logged, the lens turns red: *"WAIT — you took your Metformin at 9:04. Maya has
  been notified."* This path is deterministic graph logic, no LLM.
- **Maya's View**: her daughter gets a warm daily letter, not a surveillance feed.

## How we built it — where Jac runs

Jac is the product, not a wrapper.

- **Memory graph**: 7 node types (Person, Encounter, Medication, DoseEvent,
  HouseObject, CareCircle, DailyDigest), 6 typed edges (FamilyOf, CaresFor,
  TakesAt, RemembersWith, LastPlacedAt, AlertsTo).
- **Agents are walkers**, each with its own traversal: Matcher (identity),
  MemoryWeaver (writes encounters, folds them into rolling memory),
  SafetySentinel (dose logic), DigestWriter, plus glance/person_card/enroll/
  forget/get_graph/get_timeline auto-exposed as REST endpoints by `jac start`.
- **Meaning-Typed AI**: 6 typed `by llm()` functions (perceive → SceneReport,
  match_person → MatchResult, compose_whisper → Whisper, weave_memory,
  render_person_card, sanitize_summary) with 16 `sem` annotations.
  **Zero hand-written prompt strings in the codebase.**
- **Two-tier recognition**: local SFace embeddings (offline, deterministic,
  cosine ≥ 0.363) first; typed LLM descriptive matching as fallback.
- **Every LLM call has a deterministic fallback** — the product degrades to
  useful, never to broken, with no network.
- **iOS + Meta DAT 0.8**: camera and display in one `DeviceSession`; lens cards
  rendered with `display.send(FlexBox { Text… })`; Neural Band pinch pages
  through the Connection Card's "ask about" bullets.

## Privacy (engineered, not promised — see PRIVACY.md)

1. Embeddings are computed only at consented enrollment, never leave the user's
   private graph, and are never sent to a cloud model.
2. Frames are deleted immediately after inference, on every code path.
3. Strangers are never enrolled and never stored — an unknown face returns a
   generic whisper.
4. **Persona filter**: every encounter passes `sanitize_summary` before it
   touches the graph — third-party medical details, finances, credentials, and
   addresses are stripped. Raw conversation never enters the graph.
5. **`/walker/forget`** — the right to be forgotten as a one-call graph walk.
6. Per-user root graph = isolation by architecture.
7. The safety-critical path contains no LLM.

## Challenges

Meta's Display capability shipped nine weeks ago and has almost no code in the
wild outside Meta's own sample — we worked from the DisplayAccess sample and the
framework's `.swiftinterface` to get lens rendering working. On the Jac side,
merging two independently built backends (graph/agents and face recognition)
into one pipeline mid-hackathon meant unifying node schemas live.

## What's next

Enrollment from family photo albums, hearing-aid audio routing, Spanish and
Tagalog whispers (caregiver demographics), and a clinician view that tracks
recognition latency over time as a passive cognitive marker.

## Try it

- Repo: https://github.com/arshmeets/ReminiSense
- Hosted on JacHammer sandbox: <URL>
- Demo video: <URL>
- No glasses? The dashboard's four demo buttons run the identical pipeline.

---

## 4-minute demo script

**0:00–0:35 — the person.** "This is Eleanor. 78, early-stage Alzheimer's,
lives alone. Her daughter Maya carries the invisible load of being her memory.
Today Eleanor is wearing our glasses."

**0:35–2:15 — live demo.** Teammate walks up wearing the glasses. Look → tap.
Lens card + whisper: *"That's Maya, your daughter…"*. Projector shows the memory
graph blooming a new Encounter node. Second glance → *"You saw her this
morning…"* — **the graph learned in front of them.** Then the pill bottle:
first glance confirms the dose, second glance turns the lens red and alerts the
caregiver. Open Maya's Connection Card — the visit that just happened is
already in "Your story together."

**2:15–3:15 — where Jac runs.** Put `main.jac` on screen. Four walkers, six
typed `by llm()` functions, 16 sem annotations, zero prompt strings. Memory is
the graph; the safety path has no LLM in it. Show the Swagger tab — every
walker is an endpoint for free.

**3:15–3:45 — privacy.** "No face database to breach. Frames are deleted
instantly. Only sanitized summaries enter the graph. And forget-me is one call —
watch." Run `/walker/forget`; the person disappears from the graph live.

**3:45–4:00 — impact.** "55 million people. This is one Sunday afternoon where
a mother recognizes her daughter. That's the whole product."
