# Recall — privacy guardrails

Recall listens at events and remembers people. That only works if the trust
model is engineered in, not promised. Every guardrail below is in the code.

## 1. Faces stay in your graph
Face embeddings (128-float SFace vectors) are computed **on enrollment only**
and stored on the Person node inside your own graph. They are never sent to a
cloud model — matching is local cosine similarity against your contacts, not a
lookup against any external face database. Delete the contact and the vector
goes with it. There is no population-scale face index to breach.

## 2. Frames are ephemeral
A captured frame is used for one recognition call and then dropped. No image is
persisted to the graph, to logs, or to disk.

## 3. Only your contacts are matchable
Recognition compares against people already in *your* network. Someone you have
never enrolled produces no identity — Recall cannot identify strangers, by
construction.

## 4. Summaries, not transcripts
Raw conversation is not stored. Every ingested transcript passes through an
extraction step that keeps only professional substance — name, company, what
they're building or raising, what was promised — and drops third-party personal
details, credentials, and anything said in confidence about a company that
isn't theirs. What lands in the graph is a short factual summary, so raw
conversation can never leak from storage that never held it.

## 5. Forget is one call
`POST /walker/forget {"name": "..."}` removes a person, their interactions, and
their references in a single graph walk. Demonstrable on demand.

## 6. Your graph, your root
Everything hangs off the user's own `root` node. Jac's persistence model gives
each account an isolated graph — there is no cross-user query surface.

## 7. Capture is deliberate
Recall captures on an explicit action (tap or gesture), not by continuously
recording the room. The wearer chooses each moment it looks and listens.

## 8. No profiling
The card contains what you were told, by the person who told you. No inferred
psychographics, no scraped background, no scoring of people.
