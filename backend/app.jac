"""Recall - an AI memory layer over an Object-Spatial graph.

Two inputs, one graph. A face is resolved locally with an SFace embedding
(31ms, deterministic, works offline). Speech is transcribed on the device and
folded in by `ingest`, which extracts who was talking and what about. Both
write to the same Person node, so recognising someone later retrieves what was
actually said - not merely that you had met.

`by llm()` is used where language is the problem: cleaning live captions,
pulling structure out of a transcript, and phrasing the reminder.

Served with:  jac start app.jac --no-client --port 8420
Deployed at:  https://jac.sodhiserver.com  (auto-deploys on push to main)
"""

import cv2;
import numpy as np;
import base64;
import time;
import from jaclang.byllm.lib { Model, Image }

glob fast: Model = Model(model_name="claude-haiku-4-5-20251001");

glob DET_PATH: str = "models/face_detection_yunet_2023mar.onnx";
glob REC_PATH: str = "models/face_recognition_sface_2021dec.onnx";

# Wearable frames are shot close-up and often backlit, which sinks the face
# into shadow and hides it from the detector. Equalising the luminance channel
# first recovers the detection; measured on a hard backlit frame, this is the
# difference between needing a 0.15 score threshold and a comfortable 0.5.
glob DET_SCORE: float = 0.5;

# SFace's published cosine threshold for a same-identity match.
glob FACE_THRESHOLD: float = 0.363;

# Model handles are built once and cached. A dict is used rather than a
# rebindable glob so the lazy init needs no global reassignment.
glob _cache: dict = {};


# ---------------------------------------------------------------- perception

def _detector() -> any {
    if "det" not in _cache {
        _cache["det"] = cv2.FaceDetectorYN.create(DET_PATH, "", (320, 320), DET_SCORE, 0.3, 5000);
    }
    return _cache["det"];
}


# Lift the face out of the backlight before detection: equalise L in LAB space,
# leaving colour untouched so the embedding still sees a natural face.
def _delight(img: any) -> any {
    lab: any = cv2.cvtColor(img, cv2.COLOR_BGR2LAB);
    parts: any = cv2.split(lab);
    eq: any = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(parts[0]);
    merged: any = cv2.merge((eq, parts[1], parts[2]));
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR);
}


def _recognizer() -> any {
    if "rec" not in _cache {
        _cache["rec"] = cv2.FaceRecognizerSF.create(REC_PATH, "");
    }
    return _cache["rec"];
}


# Returns a 128-d face embedding for the largest face, or [] if none found.
def embed_face(jpeg_b64: str) -> list[float] {
    raw = base64.b64decode(jpeg_b64);
    buf: any = np.frombuffer(raw, dtype=np.uint8);
    decoded: any = cv2.imdecode(buf, cv2.IMREAD_COLOR);
    if decoded is None {
        return [];
    }
    img: any = _delight(decoded);

    det: any = _detector();
    shape: any = img.shape;
    det.setInputSize((int(shape[1]), int(shape[0])));
    faces: any = det.detect(img)[1];
    if faces is None or len(faces) == 0 {
        return [];
    }

    # Largest detected face wins - the wearer is looking at whoever is closest.
    best: any = faces[0];
    best_area: float = 0.0;
    for f in faces {
        box: any = f;
        area: float = float(box[2]) * float(box[3]);
        if area > best_area {
            best_area = area;
            best = box;
        }
    }

    rec: any = _recognizer();
    feat: any = rec.feature(rec.alignCrop(img, best));
    flat: any = feat.flatten().tolist();
    out: list[float] = [];
    for v in flat {
        out.append(float(v));
    }
    return out;
}


# People rarely re-introduce themselves in full. "Sarah" on the second meeting
# has to land on the existing "Sarah Chen" rather than forking a new node, so
# a name matches when every word of the shorter one appears in the longer.
def same_person(a: str, b: str) -> bool {
    x: str = a.strip().lower();
    y: str = b.strip().lower();
    if x == "" or y == "" {
        return False;
    }
    if x == y {
        return True;
    }
    xs = x.split();
    ys = y.split();
    short = xs;
    long_ = ys;
    if len(ys) < len(xs) {
        short = ys;
        long_ = xs;
    }
    for w in short {
        if w not in long_ {
            return False;
        }
    }
    return True;
}


# Cosine similarity between two embeddings; 0.0 if either is empty or mismatched.
def cosine(a: list[float], b: list[float]) -> float {
    if len(a) == 0 or len(b) == 0 or len(a) != len(b) {
        return 0.0;
    }
    dot: float = 0.0;
    na: float = 0.0;
    nb: float = 0.0;
    for i in range(len(a)) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if na == 0.0 or nb == 0.0 {
        return 0.0;
    }
    return dot / ((na ** 0.5) * (nb ** 0.5));
}


# --------------------------------------------------------------------- graph

node Person {
    has name: str,
        role: str = "",
        org: str = "",
        relationship: str = "",
        last_interaction: str = "",
        notes: str = "",
        interests: list[str] = [],
        followups: list[str] = [],
        face_vec: list[float] = [];
}


node Thing {
    has name: str,
        category: str = "",
        context: str = "";
}


# One meeting with one person. A face sighting and a spoken conversation are
# both Interactions - kind tells them apart - so recognising someone surfaces
# what was actually said last time, not just that they were seen.
node Interaction {
    has timestamp: str,
        summary: str,
        kind: str = "sighting",
        transcript: str = "";
}


node Topic {
    has label: str;
}


edge Knows: Root --> Person {
    has closeness: float = 0.5,
        recency: float = 0.5;
}


edge Holds: Root --> Thing {
    has closeness: float = 0.5,
        recency: float = 0.5;
}


edge Had: Person --> Interaction {
    has at: str = "";
}


edge Discussed: Person --> Topic {
    has weight: float = 1.0;
}


# ----------------------------------------------------------------- language

obj Spoken {
    has line: str;
}

sem Spoken.line = "The whisper itself: under 20 words, no greeting, no preamble, no lead-in like 'This is'. Speak it the way a friend would lean in and say it.";

def compose(name: str, role: str, org: str, relationship: str, last: str, notes: str, history: str) -> Spoken by fast(temperature=0.3, max_tokens=80);
sem compose = "Write one short line to be whispered into the wearer's earpiece, reminding them who they are looking at and surfacing the single most useful thing to raise right now. Prefer a concrete, specific detail over a generic greeting. Never use gendered pronouns for the person - their pronouns are not recorded and guessing wrong is worse than not knowing. Use their name, or 'they', or rewrite the line to need no pronoun at all.";
sem compose.name         = "The recognised person's name.";
sem compose.role         = "Their job title, may be empty.";
sem compose.org          = "The organisation they belong to, may be empty.";
sem compose.relationship = "How the wearer knows them.";
sem compose.last         = "What happened at the last interaction.";
sem compose.notes        = "Free-form notes the wearer keeps about them.";
sem compose.history      = "Summaries of recent prior encounters, most recent first. May be empty.";


obj Seen {
    has label: str,
        confidence: float;
}

sem Seen.label      = "The most prominent object in the frame, 1-3 words. Empty string if nothing identifiable.";
sem Seen.confidence = "Certainty from 0.0 to 1.0.";

def identify_thing(frame: Image) -> Seen by fast(temperature=0.0, max_tokens=200);
sem identify_thing       = "Identify the single most prominent physical object a person is holding or looking at.";
sem identify_thing.frame = "A camera frame from a wearable device.";


# ---------------------------------------------------------------- recall AI

def caption_line(heard: str, lang: str) -> str by fast(temperature=0.0, max_tokens=200);
sem caption_line = "Clean up one chunk of live speech-to-text for display on a heads-up screen: fix obvious mis-transcriptions, add punctuation, drop filler words. If the target language differs from the language spoken, translate into it. Return only the caption text - no quotes, no commentary, no speaker labels.";
sem caption_line.heard = "A raw chunk of speech-to-text from a noisy room. May be garbled.";
sem caption_line.lang  = "Target language for the caption, e.g. 'en', 'es'. Translate only if the speech is in another language.";


obj ContactInfo {
    has name: str,
        org: str,
        interests: list[str],
        followups: list[str],
        topics: list[str];
}

sem ContactInfo.name      = "The speaker's name if they introduce themselves. Empty string if never stated - never guess a name.";
sem ContactInfo.org       = "The company or organisation they say they are with. Empty if not stated.";
sem ContactInfo.interests = "What they are into, working on, or care about. Short noun phrases.";
sem ContactInfo.followups = "Anything either person promised to do or send. Short imperative phrases, e.g. 'send her the Jac repo link'. Empty list if nothing was promised.";
sem ContactInfo.topics    = "Two to five short subject labels for what was discussed, e.g. 'fintech', 'Series B', 'rock climbing'.";

def extract_contact(transcript: str) -> ContactInfo by fast(temperature=0.0, max_tokens=500);
sem extract_contact = "Pull structured contact details out of a snippet of conversation at a networking event. Record only what was actually said - leave fields empty rather than inferring. Never guess a name from a voice.";
sem extract_contact.transcript = "A transcript of what was just said, possibly by both people.";


obj Card {
    has headline: str,
        lines: list[str];
}

sem Card.headline = "One line identifying the person: name, then org or how you know them. Under 12 words.";
sem Card.lines    = "Two to four short bullets: what you last discussed, what you owe them, and one thing worth asking about now. Each under 15 words. Concrete details only - never filler like 'catch up soon'.";

def recall_card(name: str, org: str, relationship: str, interests: str, followups: str, history: str) -> Card by fast(temperature=0.3, max_tokens=400);
sem recall_card = "Build the card shown on the wearer's display when they need reminding who someone is. Ground every line in the recorded history - never invent a detail. Never use gendered pronouns for the person: their pronouns are not recorded and guessing wrong is worse than not knowing. Use their name, 'they', or rewrite to avoid the pronoun.";
sem recall_card.interests = "What they are known to be into, comma separated. May be empty.";
sem recall_card.followups = "Outstanding promises, comma separated. May be empty.";
sem recall_card.history   = "Past interactions, newest first, as 'date - what was discussed'. May be empty.";


obj Matches {
    has names: list[str],
        reason: str;
}

sem Matches.names  = "Names of the people who match the question, best first. Empty list if none do.";
sem Matches.reason = "One short sentence explaining the selection. Under 20 words.";

def pick_matches(question: str, roster: str) -> Matches by fast(temperature=0.0, max_tokens=400);
sem pick_matches = "Answer a question about who the wearer has met by choosing from the roster. Select only people the roster actually supports - an empty list is the correct answer when nobody fits.";
sem pick_matches.question = "A free-text question, e.g. 'who did I meet in fintech?'.";
sem pick_matches.roster   = "Everyone known, one per line, as 'Name | role | org | interests | topics discussed | last interaction'. Any field may be empty.";


# ------------------------------------------------------------------ walkers

walker:pub Recognize {
    """Resolve who or what is in frame, then say one useful thing about them."""

    has frame_b64: str,
        threshold: float = 0.363,
        reports: list[dict] = [];

    # Internal traversal state. These are plain JSON-safe types on purpose:
    # every walker `has` field becomes a request-body parameter, so a
    # `Person | None` here makes the endpoint un-callable (422).
    has probe: list[float] = [],
        best_score: float = 0.0,
        best_jid: str = "",
        visited: list[str] = [],
        started: float = 0.0;

    can begin with Root entry {
        self.started = time.time();
        self.probe = embed_face(self.frame_b64);
        self.visited.append("root");
        visit [-->];
    }

    can consider with Person entry {
        self.visited.append(here.name);
        sim = cosine(self.probe, here.face_vec);

        # The relationship itself sways the match: someone the wearer knows
        # well and saw recently is a likelier read than a faint acquaintance.
        weight: float = 1.0;
        links = [edge here <-:Knows:<-];
        if len(links) > 0 {
            weight = 1.0 + (0.15 * links[0].closeness) + (0.10 * links[0].recency);
        }

        scored = sim * weight;
        if scored > self.best_score {
            self.best_score = scored;
            self.best_jid = jid(here);
        }
    }

    can wrap with exit {
        elapsed = round((time.time() - self.started) * 1000.0);

        if self.best_jid == "" or self.best_score < self.threshold {
            # Silence beats a wrong name. Report the miss so the client
            # can show it without speaking anything.
            report {
                "spoken": "",
                "matched": False,
                "score": round(self.best_score, 3),
                "path": self.visited,
                "elapsed_ms": elapsed
            };
            return;
        }

        found = jobj(self.best_jid);
        if not isinstance(found, Person) {
            report {
                "spoken": "",
                "matched": False,
                "score": round(self.best_score, 3),
                "path": self.visited,
                "elapsed_ms": elapsed
            };
            return;
        }
        who: Person = found;

        # Conversations logged by `ingest` land on the same Person, so the
        # whisper can surface what was actually said, not just that we met.
        prior = [who -->[?:Interaction]];
        history: str = "";
        for e in prior[-3:] {
            history = history + e.summary + "; ";
        }

        said = compose(
            who.name, who.role, who.org,
            who.relationship, who.last_interaction, who.notes, history
        );

        stamp = time.strftime("%Y-%m-%d %H:%M:%S");
        who +>:Had(at=stamp):+> Interaction(
            timestamp=stamp,
            kind="sighting",
            summary=f"Recognised in frame; whispered: {said.line}"
        );
        self.visited.append(f"Interaction@{stamp}");

        report {
            "spoken": said.line,
            "matched": True,
            "name": who.name,
            "role": who.role,
            "org": who.org,
            "score": round(self.best_score, 3),
            "path": self.visited,
            "elapsed_ms": elapsed
        };
    }
}


walker:pub Enroll {
    """Add a person to the graph from a reference photo, live on stage."""

    has name: str,
        frame_b64: str,
        role: str = "",
        org: str = "",
        relationship: str = "",
        last_interaction: str = "",
        notes: str = "",
        closeness: float = 0.5,
        recency: float = 1.0,
        reports: list[dict] = [];

    can add with Root entry {
        vec = embed_face(self.frame_b64);
        if len(vec) == 0 {
            report {
                "enrolled": False,
                "reason": "no face detected in the reference photo"
            };
            return;
        }

        # This is the join. Someone whose conversation was already logged by
        # `ingest` must get their face attached to that SAME node - otherwise
        # recognising them later retrieves an empty history.
        who: Person | None = None;
        for p in [-->[?:Person]] {
            if p.name.lower() == self.name.lower() {
                who = p;
            }
        }
        if who is None {
            for p in [-->[?:Person]] {
                if same_person(p.name, self.name) {
                    who = p;
                }
            }
        }

        attached: bool = False;
        if who is None {
            who = here +>:Knows(closeness=self.closeness, recency=self.recency):+> Person(
                name=self.name, role=self.role, org=self.org,
                relationship=self.relationship,
                last_interaction=self.last_interaction,
                notes=self.notes, face_vec=vec
            );
        } else {
            attached = True;
        }
        person: Person = who;
        person.face_vec = vec;

        # Only fill fields the caller actually supplied, so enrolling a face
        # never blanks out detail the conversation already captured.
        if self.role != "" {
            person.role = self.role;
        }
        if self.org != "" {
            person.org = self.org;
        }
        if self.relationship != "" {
            person.relationship = self.relationship;
        }
        if self.notes != "" {
            person.notes = self.notes;
        }

        report {
            "enrolled": True,
            "name": person.name,
            "dims": len(vec),
            "attached_to_existing": attached,
            "known_interactions": len([person -->[?:Interaction]])
        };
    }
}


walker:pub Reset {
    """Empty the graph. Must be its own request: deletions land at commit time,
    so wiping and re-seeding inside one walker destroys the fresh nodes too."""

    has reports: list[dict] = [];

    can clear with Root entry {
        gone = 0;
        # A node delete cascades to its edges, but Interactions hang off Person
        # and would be orphaned rather than removed - retire those first.
        for old in [-->[?:Person]] {
            for past in [old -->[?:Interaction]] {
                del past;
            }
            del old;
            gone += 1;
        }
        for old_thing in [-->[?:Thing]] {
            del old_thing;
            gone += 1;
        }
        report {"cleared": gone};
    }
}


walker:pub Seed {
    """Populate the demo graph. Idempotent on purpose - a demo button that
    forks every person when pressed twice is a demo that breaks on stage.
    Faces are enrolled separately, on-site, via the Enroll walker."""

    has reports: list[dict] = [];

    can build with Root entry {
        added: list[str] = [];

        # (name, role, org, relationship, last_interaction, notes, closeness, recency)
        people: list[dict] = [
            {
                "name": "Sarah Chen", "role": "VP Product", "org": "Acme",
                "rel": "met at the Series A demo day",
                "last": "talked through their Series B raise",
                "notes": "still has an open question about our pricing tiers",
                "close": 0.9, "rec": 0.9
            },
            {
                "name": "Marcus Webb", "role": "Engineering Lead", "org": "Northwind",
                "rel": "former colleague",
                "last": "promised to send the migration write-up",
                "notes": "allergic to shellfish; do not suggest the oyster bar",
                "close": 0.6, "rec": 0.4
            },
            {
                "name": "Priya Raman", "role": "Partner", "org": "Fieldstone Capital",
                "rel": "introduced by Sarah",
                "last": "brief hallway chat about the seed round",
                "notes": "asked to be pinged once the metrics deck is ready",
                "close": 0.3, "rec": 0.2
            }
        ];

        for spec in people {
            known: bool = False;
            for existing in [-->[?:Person]] {
                if existing.name.lower() == spec["name"].lower() {
                    known = True;
                }
            }
            if not known {
                here +>:Knows(closeness=spec["close"], recency=spec["rec"]):+> Person(
                    name=spec["name"], role=spec["role"], org=spec["org"],
                    relationship=spec["rel"], last_interaction=spec["last"],
                    notes=spec["notes"]
                );
                added.append(spec["name"]);
            }
        }

        things: list[dict] = [
            {"name": "keys", "cat": "everyday carry",
             "ctx": "usually left on the kitchen counter", "close": 0.8, "rec": 0.9},
            {"name": "blue inhaler", "cat": "medication",
             "ctx": "two puffs, morning and night", "close": 0.7, "rec": 0.5}
        ];

        for tspec in things {
            seen_thing: bool = False;
            for et in [-->[?:Thing]] {
                if et.name.lower() == tspec["name"].lower() {
                    seen_thing = True;
                }
            }
            if not seen_thing {
                here +>:Holds(closeness=tspec["close"], recency=tspec["rec"]):+> Thing(
                    name=tspec["name"], category=tspec["cat"], context=tspec["ctx"]
                );
                added.append(tspec["name"]);
            }
        }

        report {
            "seeded": True,
            "added": added,
            "people": len([-->[?:Person]]),
            "things": len([-->[?:Thing]])
        };
    }
}


walker:pub Roster {
    """List everything currently in the graph - used by the dashboard."""

    has reports: list[dict] = [];

    can gather with Root entry {
        people: list[dict] = [];
        for p in [-->[?:Person]] {
            seen = len([p -->[?:Interaction]]);
            people.append({
                "name": p.name, "role": p.role, "org": p.org,
                "relationship": p.relationship,
                "enrolled_face": len(p.face_vec) > 0,
                "encounters": seen
            });
        }

        things: list[dict] = [];
        for t in [-->[?:Thing]] {
            things.append({
                "name": t.name, "category": t.category, "context": t.context
            });
        }

        report {"people": people, "things": things};
    }
}


# ------------------------------------------------------- recall: the speech
# side of the graph. Recognize answers "who is this"; these answer "what did
# we say". They meet on the same Person node.

walker:pub caption {
    """P0 - clean and optionally translate one chunk of live speech for the
    heads-up display. Stateless by design: captions must never wait on graph
    work, so nothing here touches the graph."""

    has text: str,
        lang: str = "en",
        reports: list[dict] = [];

    can show with Root entry {
        if self.text.strip() == "" {
            report {"display_text": ""};
            return;
        }
        report {"display_text": caption_line(self.text, self.lang)};
    }
}


walker:pub ingest {
    """P1 - fold a conversation into the graph: find-or-create the speaker,
    append the Interaction, link the Topics discussed."""

    has transcript: str,
        speaker: str = "",
        reports: list[dict] = [];

    can absorb with Root entry {
        info = extract_contact(self.transcript);

        # An explicit speaker (e.g. the person we just recognised by face)
        # always beats a name the model thinks it heard.
        name: str = self.speaker.strip();
        if name == "" {
            name = info.name.strip();
        }
        if name == "" {
            report {
                "saved": "",
                "reason": "nobody introduced themselves - not guessing a name"
            };
            return;
        }

        # Exact match wins outright; a partial name ("Sarah") only falls back
        # to the fuzzy match so two full names never collide on a first name.
        who: Person | None = None;
        for p in [-->[?:Person]] {
            if p.name.lower() == name.lower() {
                who = p;
            }
        }
        if who is None {
            for p in [-->[?:Person]] {
                if same_person(p.name, name) {
                    who = p;
                }
            }
        }

        fresh: bool = False;
        if who is None {
            who = here +>:Knows(closeness=0.5, recency=1.0):+> Person(
                name=name, org=info.org, relationship="met at an event"
            );
            fresh = True;
        }
        person: Person = who;

        if person.org == "" {
            person.org = info.org;
        }
        for i in info.interests {
            if i not in person.interests {
                person.interests.append(i);
            }
        }
        for f in info.followups {
            if f not in person.followups {
                person.followups.append(f);
            }
        }

        gist: str = ", ".join(info.topics);
        if gist == "" {
            gist = "a conversation";
        }

        stamp = time.strftime("%Y-%m-%d %H:%M:%S");
        person +>:Had(at=stamp):+> Interaction(
            timestamp=stamp,
            kind="conversation",
            summary=gist,
            transcript=self.transcript
        );
        person.last_interaction = gist;

        # Topics are nodes, not a string field, so `query` can traverse to
        # them instead of substring-matching a blob.
        added: list[str] = [];
        for t in info.topics {
            seen_topic: Topic | None = None;
            for tn in [person -->[?:Topic]] {
                if tn.label.lower() == t.lower() {
                    seen_topic = tn;
                }
            }
            if seen_topic is None {
                person +>:Discussed(weight=1.0):+> Topic(label=t);
                added.append(t);
            }
        }

        report {
            "saved": person.name,
            "new_person": fresh,
            "org": person.org,
            "topics": info.topics,
            "new_topics": added,
            "followups": person.followups
        };
    }
}


walker:pub recall {
    """P1 - the card shown when you need reminding who someone is. Pass a
    name, or "last" for whoever you spoke to most recently."""

    has name: str = "last",
        reports: list[dict] = [];

    can lookup with Root entry {
        target: Person | None = None;
        needle: str = self.name.strip().lower();

        if needle == "" or needle == "last" {
            latest: str = "";
            for p in [-->[?:Person]] {
                for e in [p -->[?:Interaction]] {
                    if e.timestamp > latest {
                        latest = e.timestamp;
                        target = p;
                    }
                }
            }
        } else {
            for p in [-->[?:Person]] {
                if needle in p.name.lower() {
                    target = p;
                }
            }
        }

        if target is None {
            report {"found": False, "reason": f"nobody matching '{self.name}'"};
            return;
        }
        who: Person = target;

        history: str = "";
        past: list[dict] = [];
        for e in [who -->[?:Interaction]][-5:] {
            history = history + e.timestamp + " - " + e.summary + "; ";
            past.append({"when": e.timestamp, "what": e.summary, "kind": e.kind});
        }

        topics: list[str] = [];
        for t in [who -->[?:Topic]] {
            topics.append(t.label);
        }

        card = recall_card(
            who.name, who.org, who.relationship,
            ", ".join(who.interests), ", ".join(who.followups), history
        );

        report {
            "found": True,
            "name": who.name,
            "org": who.org,
            "headline": card.headline,
            "lines": card.lines,
            "topics": topics,
            "followups": who.followups,
            "history": past
        };
    }
}


# ------------------------------------------------------------- iOS contract
# The iOS client calls these names. They are thin adapters over the walkers
# above so the app and the graph can evolve independently.

walker:pub glance {
    """What the glasses call on every look. Same work as Recognize, shaped the
    way the lens renderer wants it: {whisper:{text,kind,confidence}, matched}."""

    has image_b64: str,
        source: str = "glasses",
        reports: list[dict] = [];

    can look with Root entry {
        probe = embed_face(self.image_b64);

        best_score: float = 0.0;
        best_jid: str = "";
        for p in [-->[?:Person]] {
            sim = cosine(probe, p.face_vec);
            weight: float = 1.0;
            links = [edge p <-:Knows:<-];
            if len(links) > 0 {
                weight = 1.0 + (0.15 * links[0].closeness) + (0.10 * links[0].recency);
            }
            scored = sim * weight;
            if scored > best_score {
                best_score = scored;
                best_jid = jid(p);
            }
        }

        # No confident match: the lens shows a neutral line and the graph is
        # left untouched. Strangers are never recorded. jobj() must not be
        # reached with an empty jid - it raises rather than returning None.
        if best_jid == "" or best_score < FACE_THRESHOLD {
            report {
                "whisper": {"text": "", "kind": "reassurance", "confidence": round(best_score, 3)},
                "matched": ""
            };
            return;
        }

        found = jobj(best_jid);
        if not isinstance(found, Person) {
            report {
                "whisper": {"text": "", "kind": "reassurance", "confidence": round(best_score, 3)},
                "matched": ""
            };
            return;
        }
        who: Person = found;

        history: str = "";
        for e in [who -->[?:Interaction]][-3:] {
            history = history + e.summary + "; ";
        }

        said = compose(
            who.name, who.role, who.org,
            who.relationship, who.last_interaction, who.notes, history
        );

        stamp = time.strftime("%Y-%m-%d %H:%M:%S");
        who +>:Had(at=stamp):+> Interaction(
            timestamp=stamp,
            kind="sighting",
            summary=f"Seen through the {self.source}; whispered: {said.line}"
        );

        report {
            "whisper": {
                "text": said.line,
                "kind": "recognition",
                "confidence": round(best_score, 3)
            },
            "matched": who.name
        };
    }
}


# Lower-case alias - the iOS client calls /walker/enroll.
walker:pub enroll(Enroll) {}


# Alias for the iOS client and dashboard.
walker:pub seed_demo(Seed) {}


# Alias for the iOS client and dashboard.
walker:pub reset_day(Reset) {}


walker:pub forget {
    """Right to be forgotten: remove a person, their interactions, and their
    topics in one walk."""

    has name: str,
        reports: list[dict] = [];

    can erase with Root entry {
        gone: int = 0;
        for p in [-->[?:Person]] {
            if same_person(p.name, self.name) or self.name.strip().lower() in p.name.lower() {
                for e in [p -->[?:Interaction]] {
                    del e;
                }
                for t in [p -->[?:Topic]] {
                    del t;
                }
                del p;
                gone += 1;
            }
        }
        report {"forgotten": gone, "name": self.name};
    }
}


# --------------------------------------------------------------- dashboard
# The pitch calls for putting the graph on screen, so these serve the web view
# directly in the shape d3 wants: {nodes, links} and a flat event list.

def _event_ts(e: dict) -> str {
    return e["ts"];
}


walker:pub get_graph {
    """Whole graph as nodes + links, for the d3 view."""

    has reports: list[dict] = [];

    can build with Root entry {
        nodes: list[dict] = [];
        links: list[dict] = [];

        for p in [-->[?:Person]] {
            pid = jid(p);
            nodes.append({"id": pid, "label": p.name, "kind": "person"});

            for e in [p -->[?:Interaction]] {
                eid = jid(e);
                nodes.append({"id": eid, "label": e.summary, "kind": "encounter"});
                links.append({"source": pid, "target": eid, "kind": "had"});
            }
            for t in [p -->[?:Topic]] {
                tid = jid(t);
                nodes.append({"id": tid, "label": t.label, "kind": "topic"});
                links.append({"source": pid, "target": tid, "kind": "discussed"});
            }
        }

        for th in [-->[?:Thing]] {
            nodes.append({"id": jid(th), "label": th.name, "kind": "object"});
        }

        report {"nodes": nodes, "links": links};
    }
}


walker:pub get_timeline {
    """Every interaction, oldest first, for the timeline rail."""

    has reports: list[dict] = [];

    can build with Root entry {
        events: list[dict] = [];
        for p in [-->[?:Person]] {
            for e in [p -->[?:Interaction]] {
                events.append({
                    "kind": "encounter",
                    "ts": e.timestamp,
                    "text": p.name + " - " + e.summary
                });
            }
        }
        report {"events": sorted(events, key=_event_ts)};
    }
}


walker:pub person_card {
    """Markdown dossier for one person - rendered when a node is clicked."""

    has name: str,
        refresh: bool = False,
        reports: list[dict] = [];

    can build with Root entry {
        target: Person | None = None;
        needle: str = self.name.strip().lower();
        for p in [-->[?:Person]] {
            if needle in p.name.lower() {
                target = p;
            }
        }
        if not isinstance(target, Person) {
            report {"md": "**" + self.name + "** is not in the graph yet."};
            return;
        }
        who: Person = target;

        history: str = "";
        past: list[str] = [];
        for e in [who -->[?:Interaction]][-5:] {
            history = history + e.timestamp + " - " + e.summary + "; ";
            past.append("- `" + e.timestamp + "` " + e.summary);
        }

        topics: list[str] = [];
        for t in [who -->[?:Topic]] {
            topics.append(t.label);
        }

        card = recall_card(
            who.name, who.org, who.relationship,
            ", ".join(who.interests), ", ".join(who.followups), history
        );

        md: str = "# " + who.name + "\n\n";
        if who.org != "" {
            md = md + "*" + who.org + "*\n\n";
        }
        md = md + "> " + card.headline + "\n\n";

        # The lens "more" pager reads the bullets under this exact heading -
        # renaming it silently empties that screen on the glasses.
        md = md + "## Things to ask about\n";
        for l in card.lines {
            md = md + "- " + l + "\n";
        }
        if len(topics) > 0 {
            md = md + "\n## Discussed\n" + ", ".join(topics) + "\n";
        }
        if len(who.followups) > 0 {
            md = md + "\n## You owe them\n";
            for f in who.followups {
                md = md + "- " + f + "\n";
            }
        }
        if len(past) > 0 {
            md = md + "\n## History\n" + "\n".join(past) + "\n";
        }

        report {"name": who.name, "md": md};
    }
}


walker:pub query {
    """P2 - free-text question over everyone met, e.g. 'who did I meet in
    fintech?'. The graph builds the roster; the LLM only chooses from it."""

    has question: str,
        reports: list[dict] = [];

    can search with Root entry {
        roster: str = "";
        known: int = 0;
        for p in [-->[?:Person]] {
            topics: list[str] = [];
            for t in [p -->[?:Topic]] {
                topics.append(t.label);
            }
            # Role and last interaction go in too: a person who has been
            # seeded or enrolled but never had a conversation ingested has no
            # topics yet, and would otherwise be invisible to every query.
            roster = roster + p.name + " | " + p.role + " | " + p.org + " | "
                     + ", ".join(p.interests) + " | " + ", ".join(topics)
                     + " | " + p.last_interaction + "\n";
            known += 1;
        }

        if known == 0 {
            report {"matches": [], "reason": "nobody in the graph yet"};
            return;
        }

        picked = pick_matches(self.question, roster);

        # Only report people the graph actually holds - the LLM chooses, it
        # does not get to invent a contact. But it does occasionally mistype a
        # name it just read ("Priva" for "Priya"), and losing a real match over
        # one letter looks broken. So: exact, then whole-word overlap, then a
        # single unambiguous word hit. Never a guess.
        out: list[dict] = [];
        taken: list[str] = [];

        for n in picked.names {
            hit: Person | None = None;

            for p in [-->[?:Person]] {
                if p.name.lower() == n.lower() {
                    hit = p;
                }
            }
            if hit is None {
                for p in [-->[?:Person]] {
                    if same_person(p.name, n) {
                        hit = p;
                    }
                }
            }
            if hit is None {
                # Share a whole word, but only when exactly one person does -
                # two people called Sarah must never collapse into each other.
                shared: list[str] = [];
                for p in [-->[?:Person]] {
                    for w in n.lower().split() {
                        if w in p.name.lower().split() and jid(p) not in shared {
                            shared.append(jid(p));
                        }
                    }
                }
                if len(shared) == 1 {
                    found_one = jobj(shared[0]);
                    if isinstance(found_one, Person) {
                        hit = found_one;
                    }
                }
            }

            if hit is not None {
                who: Person = hit;
                pid = jid(who);
                if pid not in taken {
                    taken.append(pid);
                    out.append({
                        "name": who.name, "org": who.org,
                        "last": who.last_interaction
                    });
                }
            }
        }

        report {"matches": out, "reason": picked.reason, "searched": known};
    }
}
