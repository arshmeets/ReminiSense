# recall

**your network, remembered** — an AI networking memory for founders and investors.
Built at JacHacks SF 2026 · track: **Fintech / Open**

An AI memory layer for real life. You meet a dozen people in an hour and forget
most of it — names, who they work for, what you promised to send. Recall
listens, remembers, and reminds you.

Speech becomes a knowledge graph. A face becomes a lookup into it.

> *"Arshmeet's been focused on neural interface and gesture recognition — ask about memory recall integration."*

That line was not written by hand. It came out of the graph, from a
conversation logged minutes earlier.

Built at JacHacks SF on Jac + Jaseci.

---

## The two halves

Most of this kind of product picks one input. Recall uses both, and they
meet on the same node:

```
        speech ──► ingest ──┐
                            ├──► Person ──► Interaction ──► Topic
        face   ──► Enroll ──┘        │
                                     ▼
                            Recognize / recall
```

**Speech answers *what was said*.** A transcript goes to `ingest`, which
extracts who was speaking, what they're into, and what you owe them — then
writes an `Interaction` and links `Topic` nodes.

**A face answers *who is this*.** `Recognize` embeds the frame locally and
matches it against enrolled people.

Because `Enroll` find-or-creates, a face lands on the *same* `Person` a
conversation already created. So recognising someone later retrieves what you
actually discussed — not just that you'd met.

---

## Why identity is not an LLM call

Measured on the demo hardware:

| Step | Approach | Latency |
|---|---|---|
| Face identity | SFace embedding, local | **31ms** |
| Face identity | multimodal LLM | 1,260ms |
| Spoken line | `by llm()` over graph context | ~1,300ms |

An all-LLM pipeline burns ~2.6s in the model before capture, network, or
speech. It can also *refuse* — models are trained to decline naming a person
from a photo, which is a poor thing to discover on stage. Embeddings are
deterministic, run offline, and are 40× faster.

So `by llm()` is aimed where language is the real problem: cleaning captions,
pulling structure out of speech, and phrasing the reminder.

---

## How Jac is used

**`node` / `edge`** — the graph is the product, not a cache in front of a
database.

```jac
edge Knows: Root --> Person { has closeness: float = 0.5, recency: float = 0.5; }
edge Had:   Person --> Interaction { has at: str = ""; }
edge Discussed: Person --> Topic { has weight: float = 1.0; }
```

Edge attributes do real work — `Recognize` reads them mid-traversal so a
close, recent contact resolves more readily than a faint one:

```jac
links = [edge here <-:Knows:<-];
if len(links) > 0 {
    weight = 1.0 + (0.15 * links[0].closeness) + (0.10 * links[0].recency);
}
```

**`walker`** — each endpoint is a traversal. `Recognize` enters at root, embeds
once, visits every `Person`, scores, and composes on the way out — reporting
the path it walked alongside the answer, so the graph's work is visible.

**`by llm()`** — Meaning-Typed Programming, zero prompt strings. Signatures and
`sem` annotations *are* the prompt:

```jac
def extract_contact(transcript: str) -> ContactInfo by fast(temperature=0.0);
sem extract_contact = "Pull structured contact details out of a snippet of conversation...";
sem ContactInfo.followups = "Anything either person promised to do or send...";
```

`query` shows the division of labour: **the graph builds the roster, the LLM
only picks from it**, and every returned name is checked back against the graph
— so it can report "nobody" instead of inventing a contact.

---

## Endpoints

| Walker | Input | Output |
|---|---|---|
| `caption` | `{text, lang}` | `{display_text}` — cleans garbled STT, translates |
| `ingest` | `{transcript, speaker?}` | `{saved, topics, followups}` |
| `recall` | `{name}` or `"last"` | `{headline, lines, topics, history}` |
| `query` | `{question}` | `{matches, reason}` |
| `Recognize` | `{frame_b64}` | `{spoken, matched, score, path}` |
| `Enroll` | `{name, frame_b64}` | `{attached_to_existing, known_interactions}` |
| `get_graph` / `get_timeline` / `person_card` | — | dashboard views |

Every response is `{ok, data:{reports:[…]}}` — read `data.reports[0]`.

---

## Running it

Needs `jac 0.34.7` and an Anthropic API key.

```bash
cd backend
echo 'ANTHROPIC_API_KEY=sk-ant-...' > .env     # gitignored
jac install                                     # byLLM + opencv into .jac/venv
set -a; source .env; set +a                     # jac does NOT auto-read .env
jac start app.jac --no-client --port 8000
```

The server prints its LAN address on boot — **use that in the client**, it
changes between networks.

### Without a phone

```bash
./demo.sh hear "Hi, I'm Sarah Chen, I run product at Acme, we just closed our Series B."
./demo.sh who Sarah              # recall card
./demo.sh ask "who did I meet in fintech?"
./demo.sh caption "uh yeah so im sara chen i run product at acme" en
./demo.sh enroll "Sarah Chen" sarah.jpg
./demo.sh look frame.jpg         # recognise + spoken line
./demo.sh roster
```

Raw curl:

```bash
curl -s -X POST http://127.0.0.1:8000/walker/ingest \
     -H 'Content-Type: application/json' \
     -d '{"transcript":"Marcus Webb, engineering at Northwind, deep in a Postgres to Kafka migration."}'

curl -s -X POST http://127.0.0.1:8000/walker/query \
     -H 'Content-Type: application/json' \
     -d '{"question":"who works on databases?"}'
```

Swagger at `/docs`. The dashboard is `web/index.html` — open it with the server
running.

---

## Things learned the hard way

**Docstrings inside `def` bodies are a parse error** in 0.34.7 — fine on
walkers, fatal in functions. `by llm()` prompts belong in `sem`, not docstrings.

**`reports` is populated by the `report` keyword**, not by appending to the
field. Appending returns `[]` with no error.

**Walker `has` fields are the HTTP request body.** A `Person | None` field makes
the endpoint 422 on every call — internal traversal state has to be JSON-safe.
`Recognize` tracks its match as a `jid` string.

**Wipe-and-seed in one walker destroys what it just created** — deletions land
at commit. `Reset` and `Seed` are two calls on purpose.

**Renaming a node type invalidates the persisted graph.** Every walker then
throws `EdgeAnchor is not a valid reference`. Clear `backend/.jac/data` after
any schema change.

**Backlit frames need equalising before detection.** Wearable capture is
close-range and backlit, dropping the face into shadow. CLAHE on the luminance
channel is the difference between a desperate 0.15 detector threshold and a
comfortable 0.5. Two separate captures of the same person then matched at
**0.84 cosine** against a 0.363 threshold.

`jac check` catches none of the first five. They only appear at runtime.

---

## Deliberate behaviour

**No confident match means silence.** Below threshold, `spoken` is empty and
the client says nothing. A wrong name said with confidence is worse than none.

**Names are never guessed** — `ingest` returns `saved: ""` rather than inventing
one from a voice.

**Pronouns are never inferred.** `Person` has no pronoun field, and every
user-facing `by llm()` is told to use the name or "they".

See [PRIVACY.md](PRIVACY.md) for what is stored, what leaves the device, and
what is missing before this could touch real users.
