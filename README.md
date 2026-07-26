# ReminiSense — a memory that stays

A memory prosthetic for people with early-stage Alzheimer's, worn as Meta smart
glasses with a phone companion. Look at a person, a pill bottle, or your keys —
ReminiSense whispers who or what it is, remembers the encounter in a living
memory graph, and protects against double-dosed medication.

Built at JacHacks SF 2026.

## WHERE JAC RUNS (the whole product)

- **Memory graph**: 7 node types (Person, Encounter, Medication, DoseEvent,
  HouseObject, CareCircle, DailyDigest), 6 typed edges (FamilyOf, CaresFor,
  TakesAt, RemembersWith, LastPlacedAt, AlertsTo) — `backend/main.jac`
- **Agents as walkers** (`backend/main.impl.jac`): Matcher (traverses Person
  nodes to identify who's in frame), MemoryWeaver (writes Encounter nodes —
  the graph GROWS with every glance), SafetySentinel (deterministic double-dose
  prevention, no LLM in the safety path), plus glance/glance_cached/enroll/
  get_graph/get_timeline/daily_digest API walkers auto-exposed as REST by jac.
- **Meaning-Typed AI**: 5 typed `by llm()` functions (perceive → SceneReport,
  match_person → MatchResult, compose_whisper → Whisper, weave_memory,
  write_digest) with 14 `sem` annotations. Zero hand-written prompt strings.
  Every LLM call has a deterministic fallback — the demo cannot die on wifi.
- **Multimodal**: `perceive(img: Image) -> SceneReport by llm()` — byllm's
  native Image type on Claude vision.

## Run

```
pip install jaclang byllm            # python 3.12
export ANTHROPIC_API_KEY=...
jac start backend/main.jac --port 8000
# dashboard: serve web/index.html (any static server) and open it
```

Demo scenarios (no camera needed): POST /walker/glance_cached with
{"scenario": "maya_first" | "maya_second" | "metformin_ok" | "metformin_double"}.
Live camera: POST /walker/glance with {"image_b64": ...}.
