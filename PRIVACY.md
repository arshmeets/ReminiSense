# ReminiSense Privacy Design

ReminiSense handles intimate data — who you met and what you said. This
document describes what the system **actually does**, so it can be checked
against the code rather than taken on trust.

## What we store

**Face embeddings: yes.** `Person.face_vec` holds a 128-dimensional SFace
embedding computed locally by OpenCV. This is a biometric identifier and we
treat it as one. It is written at enrollment and persists until the Person node
is deleted.

We chose this over the alternative — asking a vision model to identify people
from descriptive notes — after measuring both. The embedding takes 31ms
on-device against 1,260ms for a model call, and it cannot be talked into naming
the wrong person. Deterministic local matching is the more privacy-respecting
of the two designs, but it is **not** "no biometrics", and describing it that
way would be false.

**Conversation transcripts: yes.** `Interaction.transcript` stores what was
said, verbatim. That is the point of the product — recall without taking notes
— but it means the graph contains real speech.

**Camera frames: no.** Frames arrive as base64, are decoded in memory, embedded,
and discarded. No image is written to the graph, to logs, or to disk.

## What leaves the device

| Data | Leaves? |
|---|---|
| Camera frame | To your own machine on the LAN. Never to a third party. |
| Face embedding | Never — computed and compared locally. |
| Transcript text | To the LLM, for extraction and phrasing. |

Face recognition works with **no network at all**. The models
(`backend/models/*.onnx`, 39MB) are vendored in the repo. Only the language
steps — captions, extraction, the spoken line — call an API.

The server binds to your LAN with anonymous `walker:pub` endpoints and no
authentication. **That is a demo posture, not a deployment posture.** Anyone on
the same network can read the whole graph. Do not run this on a public network
with real people's data in it.

## Deliberate refusals

These are enforced in code, not aspiration:

**No confident match means silence.** Below the 0.363 cosine threshold the
walker returns `spoken: ""` and the client says nothing. A wrong name whispered
with confidence is worse than no name at all.

**Names are never guessed.** `ingest` records a name only if someone actually
states it — it will not infer one from a voice, a face, or context. It returns
`saved: ""` instead.

**Pronouns are never inferred.** `Person` has no pronoun field, and every
`by llm()` that produces user-facing text is instructed to use the person's
name or "they", never to guess from a name or an appearance.

## Deletion

Deleting a `Person` cascades to their edges; `Reset` clears the graph. Because
Jac persists the graph to disk, deletion is only fully complete once
`backend/.jac/data` is cleared — `Reset` handles the graph, the directory is
the backstop.

## What is missing before this touches real users

Named plainly, because a hackathon build should not imply more than it has:

- **Authentication.** Every endpoint is anonymous today.
- **Encryption at rest** for `face_vec` and `transcript`.
- **Consent from the person being remembered.** Only the wearer consents right
  now. The other person is enrolled without being asked, which is the sharpest
  ethical edge in this design and is not solved.
- **Retention limits** on transcripts.
- **A `forget` endpoint.** Deletion currently means `Reset` or removing the
  node directly; there is no per-person right-to-be-forgotten call.

None of these are implemented.
