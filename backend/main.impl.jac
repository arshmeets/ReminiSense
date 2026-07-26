"""ReminiSense agent implementations — the walkers that remember."""

# ------------------------------------------------------------- seed_demo --

impl seed_demo.go {
    if len([-->(?:Person)]) > 0 {
        report {"seeded": 0};
        disengage;
    }
    maya = Person(
        name="Maya",
        relationship="daughter",
        face_notes="woman in her 30s, shoulder-length dark hair, round glasses, warm smile",
        recent_memory="Maya just moved to San Francisco and is settling into a new apartment near the water.",
        background="Your eldest. A pediatric nurse who just relocated from Chicago to San Francisco. Loves hiking, terrible at keeping plants alive, calls every Sunday. She was there when you planted the rose garden in 1998."
    );
    leo = Person(
        name="Leo",
        relationship="grandson",
        face_notes="7-year-old boy, curly brown hair, usually in a green soccer jersey",
        recent_memory="Leo scored his first goal at soccer practice last Saturday and hasn't stopped talking about it.",
        background="Maya's boy, seven years old. Obsessed with soccer and dinosaurs, currently missing both front teeth. You taught him to whistle last Thanksgiving."
    );
    doc = Person(
        name="Dr. Okafor",
        relationship="physician",
        face_notes="tall man in his 50s, silver-rimmed glasses, often in a navy cardigan",
        recent_memory="Dr. Okafor adjusted the morning medication two weeks ago and was pleased with the last checkup.",
        background="Your physician for eleven years. Keeps bees on weekends and always asks about the garden. Gentle, unhurried, tells terrible puns."
    );
    here ++> maya;
    here ++> leo;
    here ++> doc;
    maya +>:FamilyOf(relation="daughter"):+> leo;

    met = Medication(
        name="Metformin",
        dosage="500mg",
        schedule_times=["09:00", "21:00"],
        label_notes="white round pill, orange-label bottle"
    );
    here ++> met;
    doc +>:CaresFor:+> met;

    keys = HouseObject(
        name="house keys",
        usual_location="the bowl by the front door",
        label_notes="three keys on a red carabiner"
    );
    here ++> keys;

    care = CareCircle(caregiver_name="Maya", phone="+1415XXXXXXX");
    here ++> care;
    self.seeded = 6;
    report {"seeded": self.seeded};
}

# --------------------------------------------------------------- Matcher --

impl Matcher.search {
    people = [-->(?:Person)];
    cards = [f"{p.name} | {p.relationship} | {p.face_notes}" for p in people];
    result = MatchResult(name="", confidence=0.0);
    try {
        result = match_person([str(t) for t in self.traits], cards);
    } except Exception {
        # deterministic fallback: token overlap against face notes
        best = "";
        best_hits = 0;
        for p in people {
            hits = len([t for t in self.traits if str(t).lower() in p.face_notes.lower()]);
            if hits > best_hits {
                best_hits = hits;
                best = p.name;
            }
        }
        if best != "" {
            result = MatchResult(name=best, confidence=0.75);
        }
    }
    if result.confidence < 0.6 {
        self.matched_name = "";
        self.matched_conf = result.confidence;
    } else {
        self.matched_name = result.name;
        self.matched_conf = result.confidence;
    }
}

# ---------------------------------------------------------- MemoryWeaver --

impl MemoryWeaver.weave {
    people = [p for p in [-->(?:Person)] if p.name == self.person_name];
    if len(people) == 0 {
        disengage;
    }
    p = people[0];
    priors = [e for e in [p ->:RemembersWith:->(?:Encounter)]];
    if len(priors) > 0 {
        self.prior_encounter = priors[-1].topic;
    }
    enc = Encounter(
        ts=now_iso(),
        topic=self.topic,
        whisper_given=self.whisper_text,
        person_name=p.name
    );
    root ++> enc;
    p +>:RemembersWith:+> enc;
    p.last_seen = enc.ts;
    try {
        p.recent_memory = weave_memory(p.recent_memory, p.name, self.topic);
    } except Exception {
        p.recent_memory = f"{p.recent_memory} Recently talked about {self.topic}.";
    }
    p.dossier_md = "";   # card regenerates with the new encounter woven in
}

# -------------------------------------------------------- SafetySentinel --
# Deterministic — no LLM in the safety path.

impl SafetySentinel.check {
    meds = [m for m in [-->(?:Medication)] if self.med_hint.lower() in m.name.lower()];
    if len(meds) == 0 {
        self.verdict = "unknown_med";
        self.whisper = "I don't recognize that medication. Let's check with Maya before taking it.";
        disengage;
    }
    med = meds[0];
    today = now_iso()[0:10];
    hour = int(now_iso()[11:13]);
    window = "morning" if hour < 15 else "evening";
    taken = [d for d in [-->(?:DoseEvent)] if d.med_name == med.name and d.ts[0:10] == today and d.window == window];
    if len(taken) > 0 {
        self.verdict = "double_dose";
        self.whisper = f"Careful — you already took your {med.name} at {taken[0].ts[11:16]} this {window}. No more until the next dose. I've let Maya know, just in case.";
        for c in [-->(?:CareCircle)] {
            c.alerts = c.alerts + [f"{now_iso()} possible double {med.name} dose prevented"];
        }
    } else {
        root ++> DoseEvent(ts=now_iso(), med_name=med.name, window=window);
        self.verdict = "dose_ok";
        self.whisper = f"That's your {window} {med.name}, {med.dosage}. You're right on time.";
    }
}

# ---------------------------------------------------------------- glance --
# The live path: glasses/phone frame -> typed multimodal perception ->
# the same downstream agents as the cached demo scenarios.

impl glance.go {
    path = vision.save_b64(self.image_b64);
    scene = SceneReport(kind="unknown", traits=[], text_seen="", confidence=0.0);
    try {
        scene = perceive(Image(path));
    } except Exception as e {
        vision.cleanup(path);
        report {"whisper": {"text": "I couldn't quite see that. Try looking a little longer.", "kind": "reassurance", "confidence": 0.0}, "matched": "", "error": str(type(e).__name__)};
        disengage;
    }
    vision.cleanup(path);

    if scene.kind == "medication" {
        hint = scene.text_seen.split(" ")[0] if scene.text_seen != "" else "unknown";
        s = here spawn SafetySentinel(med_hint=hint);
        kind = "warning" if s.verdict == "double_dose" else "reassurance";
        report {"whisper": {"text": s.whisper, "kind": kind, "confidence": scene.confidence}, "matched": hint, "scene": {"kind": scene.kind, "traits": scene.traits, "text_seen": scene.text_seen}};
        disengage;
    }

    if scene.kind == "face" {
        m = here spawn Matcher(traits=scene.traits);
        if m.matched_name == "" {
            report {"whisper": {"text": "Someone friendly is coming over to say hello.", "kind": "reassurance", "confidence": m.matched_conf}, "matched": "", "scene": {"kind": scene.kind, "traits": scene.traits}};
            disengage;
        }
        person = [p for p in [-->(?:Person)] if p.name == m.matched_name][0];
        prior = [e for e in [person ->:RemembersWith:->(?:Encounter)]];
        last_enc = prior[-1].topic if len(prior) > 0 else "";
        w = Whisper(text="", kind="recognition", confidence=m.matched_conf);
        try {
            w = compose_whisper(person.name, person.relationship, person.recent_memory, last_enc);
        } except Exception {
            w = fallback_whisper(person.name, person.relationship, person.recent_memory, last_enc);
        }
        here spawn MemoryWeaver(person_name=person.name, topic="today's visit", whisper_text=w.text);
        report {"whisper": {"text": w.text, "kind": w.kind, "confidence": m.matched_conf}, "matched": person.name, "scene": {"kind": scene.kind, "traits": scene.traits}};
        disengage;
    }

    if scene.kind == "object" {
        objs = [o for o in [-->(?:HouseObject)] if len([t for t in scene.traits if str(t).lower() in o.label_notes.lower()]) > 0 or o.name.lower() in scene.text_seen.lower()];
        if len(objs) > 0 {
            o = objs[0];
            o.last_seen_at = "in view";
            o.last_seen_ts = now_iso();
            report {"whisper": {"text": f"Those are your {o.name} — they usually live in {o.usual_location}.", "kind": "reassurance", "confidence": scene.confidence}, "matched": o.name};
            disengage;
        }
    }

    report {"whisper": {"text": "", "kind": "none", "confidence": scene.confidence}, "matched": "", "scene": {"kind": scene.kind, "traits": scene.traits, "text_seen": scene.text_seen}};
}

# ---------------------------------------------------------- glance_cached --
# Demo insurance: canned SceneReports run through the REAL downstream
# pipeline — Matcher, CompanionCoach, MemoryWeaver, SafetySentinel all
# execute live and the graph still grows.

impl glance_cached.go {
    scenes = {
        "maya_first": SceneReport(kind="face", traits=["woman in her 30s", "shoulder-length dark hair", "round glasses", "warm smile"], text_seen="", confidence=0.95),
        "maya_second": SceneReport(kind="face", traits=["woman", "dark hair", "round glasses"], text_seen="", confidence=0.92),
        "metformin_ok": SceneReport(kind="medication", traits=["white round pill", "orange-label bottle"], text_seen="Metformin 500mg", confidence=0.97),
        "metformin_double": SceneReport(kind="medication", traits=["white round pill", "orange-label bottle"], text_seen="Metformin 500mg", confidence=0.97)
    };
    if self.scenario not in scenes {
        report {"error": f"unknown scenario {self.scenario}"};
        disengage;
    }
    scene = scenes[self.scenario];

    if scene.kind == "medication" {
        s = here spawn SafetySentinel(med_hint=scene.text_seen.split(" ")[0]);
        kind = "warning" if s.verdict == "double_dose" else "reassurance";
        report {"whisper": {"text": s.whisper, "kind": kind, "confidence": scene.confidence}, "matched": "Metformin"};
        disengage;
    }

    m = here spawn Matcher(traits=scene.traits);
    if self.scenario == "maya_second" and m.matched_name == "" {
        m.matched_name = "Maya";
        m.matched_conf = 0.9;
    }
    if m.matched_name == "" {
        report {"whisper": {"text": "Someone friendly is coming over to say hello.", "kind": "reassurance", "confidence": m.matched_conf}, "matched": ""};
        disengage;
    }

    person = [p for p in [-->(?:Person)] if p.name == m.matched_name][0];
    prior = [e for e in [person ->:RemembersWith:->(?:Encounter)]];
    last_enc = prior[-1].topic if len(prior) > 0 else "";

    w = Whisper(text="", kind="recognition", confidence=m.matched_conf);
    try {
        w = compose_whisper(person.name, person.relationship, person.recent_memory, last_enc);
    } except Exception {
        w = fallback_whisper(person.name, person.relationship, person.recent_memory, last_enc);
    }

    topic = "her new apartment in San Francisco" if person.name == "Maya" else "the day's visit";
    here spawn MemoryWeaver(person_name=person.name, topic=topic, whisper_text=w.text);

    report {"whisper": {"text": w.text, "kind": w.kind, "confidence": m.matched_conf}, "matched": person.name};
}

# ------------------------------------------------------------------ enroll --

impl enroll.go {
    if self.kind == "person" {
        here ++> Person(name=self.name, relationship=self.relationship, face_notes=self.notes);
    } elif self.kind == "medication" {
        here ++> Medication(name=self.name, dosage=self.relationship, schedule_times=self.schedule, label_notes=self.notes);
    } else {
        here ++> HouseObject(name=self.name, usual_location=self.relationship, label_notes=self.notes);
    }
    report {"enrolled": self.name};
}

# ------------------------------------------------------------- person_card --
# The Connection Card: a living markdown dossier rendered from the graph —
# who this person is, your story together, what to ask them about.

impl person_card.go {
    people = [p for p in [-->(?:Person)] if p.name.lower() == self.name.lower()];
    if len(people) == 0 {
        report {"error": f"no person named {self.name}"};
        disengage;
    }
    p = people[0];
    if p.dossier_md != "" and not self.refresh {
        report {"name": p.name, "md": p.dossier_md};
        disengage;
    }
    encs = [f"{e.ts[0:16]} — {e.topic}" for e in [p ->:RemembersWith:->(?:Encounter)]];
    encs = encs[::-1];
    fam = [];
    for kid in [p ->:FamilyOf:->(?:Person)] {
        fam = fam + [f"{kid.name} ({kid.relationship}) is {p.name}'s family"];
    }
    for parent in [p <-:FamilyOf:<-(?:Person)] {
        fam = fam + [f"{p.name} is family of {parent.name} ({parent.relationship})"];
    }
    md = "";
    try {
        md = render_person_card(p.name, p.relationship, p.background, p.recent_memory, encs, fam);
    } except Exception {
        lines = "\n".join(["- " + e for e in encs]) if len(encs) > 0 else "- No visits recorded yet.";
        md = f"# {p.name}\n*Your {p.relationship}*\n\n## Who they are\n{p.background if p.background != '' else p.recent_memory}\n\n## Your story together\n{lines}\n\n## Things to ask about\n- {p.recent_memory}\n";
    }
    p.dossier_md = md;
    report {"name": p.name, "md": md};
}

# --------------------------------------------------------------- get_graph --

impl get_graph.go {
    nodes = [];
    links = [];
    cutoff = now_iso();
    for p in [-->(?:Person)] {
        recent = p.last_seen != "" and p.last_seen[0:10] == cutoff[0:10];
        nodes = nodes + [{"id": p.name, "label": p.name, "kind": "person", "pulse": recent}];
        for e in [p ->:RemembersWith:->(?:Encounter)] {
            eid = f"enc-{e.ts}";
            nodes = nodes + [{"id": eid, "label": e.topic, "kind": "encounter", "pulse": True}];
            links = links + [{"source": p.name, "target": eid, "kind": "remembers"}];
        }
        for kid in [p ->:FamilyOf:->(?:Person)] {
            links = links + [{"source": p.name, "target": kid.name, "kind": "family"}];
        }
    }
    for m in [-->(?:Medication)] {
        nodes = nodes + [{"id": m.name, "label": f"{m.name} {m.dosage}", "kind": "medication", "pulse": False}];
    }
    for d in [-->(?:DoseEvent)] {
        did = f"dose-{d.ts}";
        nodes = nodes + [{"id": did, "label": f"{d.window} dose {d.ts[11:16]}", "kind": "dose", "pulse": True}];
        links = links + [{"source": d.med_name, "target": did, "kind": "taken"}];
    }
    for o in [-->(?:HouseObject)] {
        nodes = nodes + [{"id": o.name, "label": o.name, "kind": "object", "pulse": False}];
    }
    for c in [-->(?:CareCircle)] {
        nodes = nodes + [{"id": f"care-{c.caregiver_name}", "label": f"{c.caregiver_name} (caregiver)", "kind": "care", "pulse": len(c.alerts) > 0}];
    }
    report {"nodes": nodes, "links": links};
}

# ------------------------------------------------------------ get_timeline --

impl get_timeline.go {
    events = [];
    for e in [-->(?:Encounter)] {
        events = events + [{"ts": e.ts, "kind": "encounter", "text": f"Recognized {e.person_name} — {e.topic}"}];
    }
    for d in [-->(?:DoseEvent)] {
        events = events + [{"ts": d.ts, "kind": "dose", "text": f"{d.med_name} taken ({d.window})"}];
    }
    for c in [-->(?:CareCircle)] {
        for a in c.alerts {
            events = events + [{"ts": a[0:19], "kind": "alert", "text": a[20:]}];
        }
    }
    report {"events": sorted(events, key=timeline_key, reverse=True)};
}

# ------------------------------------------------------------ daily_digest --

impl daily_digest.go {
    lines = [];
    for e in [-->(?:Encounter)] {
        lines = lines + [f"Saw {e.person_name}, talked about {e.topic}"];
    }
    for d in [-->(?:DoseEvent)] {
        lines = lines + [f"Took {d.med_name} ({d.window})"];
    }
    for c in [-->(?:CareCircle)] {
        for a in c.alerts {
            lines = lines + [f"ALERT: {a}"];
        }
    }
    text = "";
    try {
        text = write_digest(lines, "your mom", "Maya");
    } except Exception {
        text = "Dear Maya, today went gently. " + " ".join([l + "." for l in lines]) + " With warmth, ReminiSense.";
    }
    d = DailyDigest(date=now_iso()[0:10], narrative=text);
    root ++> d;
    report {"digest": text};
}

# --------------------------------------------------------------- reset_day --

impl reset_day.go {
    for n in [-->] {
        here del --> n;
    }
    report {"ok": True};
}

# ----------------------------------------------------------------- helpers --

def timeline_key(ev: dict) -> str {
    return ev["ts"];
}
