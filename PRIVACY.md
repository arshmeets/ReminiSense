# Recall — privacy guardrails

Recall listens at events and remembers people. That only works if the trust
model is engineered in, not promised. Every guardrail below is in the code.

## 1. Faces stay in your graph
Face embeddings (128-float SFace vectors) are computed **on enrollment only**
and stored on the Person node inside your own graph. They are never sent to a
cloud model — matching is local cosine similarity against your contacts, not a
lookup against any external face database. Delete the contact and the vector
goes with it. There is no population-scale face index to breach.

## 2. Recognition frames are ephemeral; the enrolment photo is kept
Every frame captured while looking around is used for one recognition call and
then dropped — never written to the graph, to logs, or to disk. The one
exception is deliberate: the single frame you enrol someone from is stored on
their Person node as `photo_b64` (~17KB of JPEG) so a face can be shown beside a
name. That is a stored photograph of a person, and `forget` deletes it with
them.

## 3. Only your contacts are matchable
Recognition compares against people already in *your* network. Someone you have
never enrolled produces no identity — Recall cannot identify strangers, by
construction.

## 4. Summaries are extracted — and the transcript is kept alongside them
Every ingested transcript passes through an extraction step that pulls out the
professional substance: name, company, what they're building or raising, what
was promised. That summary is what the cards and queries are built from.

The raw transcript is **also** retained, on `Interaction.transcript`, in plain
text. It is what makes "what did we actually say?" answerable later. Anyone with
read access to the graph can read it verbatim, so treat the store as holding
real conversation, not just derived summaries.

## 5. Forget is one call
`POST /walker/forget {"name": "..."}` removes a person, their interactions, and
their references in a single graph walk. Demonstrable on demand.

## 6. One graph, no auth — this build is a demo, not a deployment
Jac's persistence model *can* give each account an isolated graph off its own
`root`. This build does not use it. All 17 walkers are `walker:pub`, meaning
anonymous: there is a single shared graph and no authentication on any endpoint.

Anyone who can reach the host can read every contact, every photo, and every
transcript in it. That is an acceptable trade for a hackathon demo on a known
URL, and it is the first thing that has to change before this is pointed at real
people's conversations. Per-user roots, login, and encryption at rest are all
unimplemented.

## 7. Capture is deliberate
Recall captures on an explicit action (tap or gesture), not by continuously
recording the room. The wearer chooses each moment it looks and listens.

## 8. No profiling
The card contains what you were told, by the person who told you. No inferred
psychographics, no scraped background, no scoring of people.
