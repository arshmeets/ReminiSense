"""ReminiSense — a memory prosthetic for people living with early-stage Alzheimer's.

Object-Spatial architecture: the patient's life is a persistent property
graph. Every recognition agent is a walker that physically traverses it.
Every LLM judgment is a typed `by llm()` function whose entire prompt
surface is `sem` annotations — zero hand-written prompt strings.
The graph GROWS with every glance: seeing someone writes an Encounter,
and the next whisper remembers it.
"""

import os;
import vision;
import from datetime { datetime }
import from byllm.lib { Model, Image }

glob llm = Model(model_name=os.environ.get("BYLLM_MODEL", "claude-sonnet-4-6"));

# ---------------------------------------------------------------- schema --

node Person {
    has name: str;
    has relationship: str;
    has face_notes: str = "";
    has recent_memory: str = "";
    has last_seen: str = "";
    has background: str = "";
    has dossier_md: str = "";
}

node Encounter {
    has ts: str;
    has topic: str;
    has whisper_given: str;
    has person_name: str;
}

node Medication {
    has name: str;
    has dosage: str;
    has schedule_times: list = [];
    has label_notes: str = "";
}

node DoseEvent {
    has ts: str;
    has med_name: str;
    has window: str = "";
}

node HouseObject {
    has name: str;
    has usual_location: str;
    has label_notes: str = "";
    has last_seen_at: str = "";
    has last_seen_ts: str = "";
}

node CareCircle {
    has caregiver_name: str;
    has phone: str = "";
    has alerts: list = [];
}

node DailyDigest {
    has date: str;
    has narrative: str;
}

edge FamilyOf {
    has relation: str = "";
}

edge CaresFor {}

edge TakesAt {
    has time_of_day: str = "";
}

edge RemembersWith {}

edge AlertsTo {}

# ------------------------------------------------- meaning-typed program --
# The entire prompt surface of ReminiSense lives in these sem annotations.

obj SceneReport {
    has kind: str;
    has traits: list[str];
    has text_seen: str;
    has confidence: float;
}

obj MatchResult {
    has name: str;
    has confidence: float;
}

obj Whisper {
    has text: str;
    has kind: str;
    has confidence: float;
}

def perceive(img: Image) -> SceneReport by llm();
sem perceive = "Analyze one camera frame from smart glasses worn by a person with early-stage Alzheimer's. Classify what dominates the frame: kind='face' (a person is the subject), 'medication' (a pill bottle, blister pack, or medicine label), 'object' (a notable household item like keys or a wallet), or 'unknown'. traits lists concise visual descriptors (for faces: apparent age range, hair, glasses, clothing; for items: shape, color, label details). text_seen is any legible text, verbatim. confidence is 0-1.";

def match_person(traits: list[str], candidates: list[str]) -> MatchResult by llm();
sem match_person = "Match observed facial/appearance traits against known people's face notes. Return the best-matching person's name and a 0-1 confidence. If nothing plausibly matches, return name='' and confidence 0.";
sem match_person.traits = "Visual traits observed through the wearer's glasses right now.";
sem match_person.candidates = "Known people, each formatted as 'Name | relationship | face notes'.";

def compose_whisper(name: str, relationship: str, recent_memory: str, last_encounter: str) -> Whisper by llm();
sem compose_whisper = "Compose the short prompt whispered into the ear of a person with early-stage Alzheimer's when they see someone familiar. Warm, max 2 sentences: who this is, one recent detail to spark conversation. Never mention the diagnosis, never say 'you forgot', never sound clinical. kind is 'recognition'.";
sem compose_whisper.recent_memory = "Rolling summary of the wearer's recent history with this person.";
sem compose_whisper.last_encounter = "The most recent encounter today, empty if none — if present, gently reference it ('You saw her this morning...').";

def weave_memory(old_memory: str, person: str, topic: str) -> str by llm();
sem weave_memory = "Fold a new encounter into a person's rolling 2-3 sentence memory summary, keeping the most conversation-sparking details. Plain text.";

def render_person_card(name: str, relationship: str, background: str, recent_memory: str, encounters: list[str], family: list[str]) -> str by llm();
sem render_person_card = "Write a warm one-page markdown 'Connection Card' that helps a person with early-stage Alzheimer's (or their caregiver) reconnect with someone before or during a visit. Sections: '# <Name>' with relationship subtitle; '## Who they are' (2-3 sentences of background); '## Your story together' (from encounter history, newest first); '## Things to ask about' (3 bullet conversation starters grounded in real details); '## Good to know' (gentle tips, family links). Warm, plain language, never clinical, never mentions the diagnosis.";
sem render_person_card.encounters = "Recent encounters, newest first, formatted 'date — topic'.";
sem render_person_card.family = "Family relationships known in the graph, e.g. 'Leo is Maya's son'.";

def sanitize_summary(text: str) -> str by llm();
sem sanitize_summary = "Privacy filter for a memory-support app. Rewrite a conversation topic/summary keeping only warm, neutral, conversation-safe content. REMOVE entirely: third parties' medical details, finances/money amounts, credentials/numbers, exact addresses, conflicts or anything embarrassing. Return the safe summary only, under 20 words. If nothing safe remains, return 'a nice visit'.";

def write_digest(events: list[str], patient: str, caregiver: str) -> str by llm();
sem write_digest = "Write today's short warm letter (3-4 sentences) from a memory-support app to a caregiver about their parent's day: encounters, medications taken, anything to gently watch. Address the caregiver by name. Plain text, no markdown.";

# ------------------------------------------------------------ fallbacks --

def fallback_whisper(name: str, relationship: str, memory: str, last_enc: str) -> Whisper {
    seen = f" You saw them earlier today — you talked about {last_enc}." if last_enc != "" else "";
    m = f" {memory}" if memory != "" else "";
    return Whisper(
        text=f"That's {name}, your {relationship}.{m}{seen}",
        kind="recognition",
        confidence=0.85
    );
}

def now_iso() -> str {
    return datetime.now().isoformat()[0:19];
}

# ----------------------------------------------------------------- agents --

walker :pub seed_demo {
    has seeded: int = 0;
    can go with Root entry;
}

walker Matcher {
    has traits: list = [];
    has matched_name: str = "";
    has matched_conf: float = 0.0;
    can search with Root entry;
}

walker MemoryWeaver {
    has person_name: str = "";
    has topic: str = "";
    has whisper_text: str = "";
    has prior_encounter: str = "";
    can weave with Root entry;
}

walker SafetySentinel {
    has med_hint: str = "";
    has verdict: str = "";
    has whisper: str = "";
    can check with Root entry;
}

walker :pub glance {
    has image_b64: str;
    has source: str = "glasses";
    can go with Root entry;
}

walker :pub glance_cached {
    has scenario: str;
    can go with Root entry;
}

walker :pub enroll {
    has kind: str;
    has name: str;
    has relationship: str = "";
    has notes: str = "";
    has schedule: list = [];
    can go with Root entry;
}

walker :pub person_card {
    has name: str;
    has refresh: bool = False;
    can go with Root entry;
}

walker :pub get_graph {
    can go with Root entry;
}

walker :pub get_timeline {
    can go with Root entry;
}

walker :pub daily_digest {
    can go with Root entry;
}

walker :pub forget {
    has name: str;
    can go with Root entry;
}

walker :pub reset_day {
    can go with Root entry;
}

with entry {
    print("ReminiSense core loaded — jac start backend/main.jac to serve.");
}
