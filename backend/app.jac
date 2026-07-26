"""ReminiSense - ambient recall over an Object-Spatial graph.

A frame arrives from the wearable. Identity is resolved locally with a face
embedding (fast, deterministic, offline). The graph supplies the context, and
`by llm()` turns that context into one short spoken line.

Served with:  jac start app.jac --no-client
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
        face_vec: list[float] = [];
}


node Thing {
    has name: str,
        category: str = "",
        context: str = "";
}


node Encounter {
    has timestamp: str,
        summary: str;
}


edge Knows: Root --> Person {
    has closeness: float = 0.5,
        recency: float = 0.5;
}


edge Holds: Root --> Thing {
    has closeness: float = 0.5,
        recency: float = 0.5;
}


edge Met: Person --> Encounter {
    has at: str = "";
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

        prior = [who -->[?:Encounter]];
        history: str = "";
        for e in prior[-3:] {
            history = history + e.summary + "; ";
        }

        said = compose(
            who.name, who.role, who.org,
            who.relationship, who.last_interaction, who.notes, history
        );

        stamp = time.strftime("%Y-%m-%d %H:%M:%S");
        who +>:Met(at=stamp):+> Encounter(
            timestamp=stamp,
            summary=f"Recognised in frame; whispered: {said.line}"
        );
        self.visited.append(f"Encounter@{stamp}");

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

        p = Person(
            name=self.name, role=self.role, org=self.org,
            relationship=self.relationship,
            last_interaction=self.last_interaction,
            notes=self.notes, face_vec=vec
        );
        here +>:Knows(closeness=self.closeness, recency=self.recency):+> p;

        report {
            "enrolled": True,
            "name": self.name,
            "dims": len(vec)
        };
    }
}


walker:pub Reset {
    """Empty the graph. Must be its own request: deletions land at commit time,
    so wiping and re-seeding inside one walker destroys the fresh nodes too."""

    has reports: list[dict] = [];

    can clear with Root entry {
        gone = 0;
        # A node delete cascades to its edges, but Encounters hang off Person
        # and would be orphaned rather than removed - retire those first.
        for old in [-->[?:Person]] {
            for past in [old -->[?:Encounter]] {
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
    """Populate the demo graph. Faces are enrolled separately, on-site, via
    the Enroll walker - seeded people start face-less on purpose."""

    has reports: list[dict] = [];

    can build with Root entry {
        here +>:Knows(closeness=0.9, recency=0.9):+> Person(
            name="Sarah Chen", role="VP Product", org="Acme",
            relationship="met at the Series A demo day",
            last_interaction="talked through their Series B raise",
            notes="still has an open question about our pricing tiers"
        );

        here +>:Knows(closeness=0.6, recency=0.4):+> Person(
            name="Marcus Webb", role="Engineering Lead", org="Northwind",
            relationship="former colleague",
            last_interaction="promised to send the migration write-up",
            notes="allergic to shellfish; do not suggest the oyster bar"
        );

        here +>:Knows(closeness=0.3, recency=0.2):+> Person(
            name="Priya Raman", role="Partner", org="Fieldstone Capital",
            relationship="introduced by Sarah",
            last_interaction="brief hallway chat about the seed round",
            notes="asked to be pinged once the metrics deck is ready"
        );

        here +>:Holds(closeness=0.8, recency=0.9):+> Thing(
            name="keys", category="everyday carry",
            context="usually left on the kitchen counter"
        );

        here +>:Holds(closeness=0.7, recency=0.5):+> Thing(
            name="blue inhaler", category="medication",
            context="two puffs, morning and night"
        );

        report {
            "seeded": True,
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
            seen = len([p -->[?:Encounter]]);
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
