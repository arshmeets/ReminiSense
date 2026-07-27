"""Tests for the Recall backend.

Run with:  jac clean --data --force && jac test app.jac

Deliberately covers the logic that has actually broken in this codebase rather
than the parts that were never in doubt: entity resolution, Seed idempotency,
the face/conversation join, and the deterministic caption path. Nothing here
calls an LLM, so the suite needs no API key and gives the same answer twice.

Each test gets a clean root in this Jac version, so every graph test seeds the
state it needs rather than relying on an earlier test having run. Assertions
count what the test itself created or filter by a unique field.
"""

# ---------------------------------------------------------- pure functions

test "same_person matches an exact name" {
    assert same_person("Sarah Chen", "Sarah Chen");
}

test "same_person is case and whitespace insensitive" {
    assert same_person("  sarah chen ", "Sarah Chen");
}

test "same_person matches a first name to a full name" {
    # The bug this exists for: "Sarah again" on a second meeting forked a
    # duplicate Person instead of landing on the existing "Sarah Chen".
    assert same_person("Sarah", "Sarah Chen");
    assert same_person("Sarah Chen", "Sarah");
}

test "same_person matches on surname alone" {
    assert same_person("Chen", "Sarah Chen");
}

test "same_person rejects different people" {
    assert not same_person("Sarah Chen", "Marcus Webb");
    assert not same_person("Sarah Chen", "Sarah Kim");
}

test "same_person rejects empty input rather than matching everything" {
    assert not same_person("", "Sarah Chen");
    assert not same_person("Sarah Chen", "");
    assert not same_person("   ", "Sarah Chen");
}

test "cosine of a vector with itself is 1" {
    v = [1.0, 2.0, 3.0, 4.0];
    assert cosine(v, v) > 0.9999;
}

test "cosine of orthogonal vectors is 0" {
    assert cosine([1.0, 0.0], [0.0, 1.0]) < 0.0001;
}

test "cosine is 0 for empty or mismatched vectors, never an error" {
    assert cosine([], [1.0, 2.0]) == 0.0;
    assert cosine([1.0, 2.0], []) == 0.0;
    assert cosine([1.0, 2.0], [1.0, 2.0, 3.0]) == 0.0;
}

test "cosine survives a zero vector without dividing by zero" {
    assert cosine([0.0, 0.0], [1.0, 2.0]) == 0.0;
}

test "embed_face returns empty for input that is not an image" {
    # Must degrade to "no face" rather than raising - the walkers treat an
    # empty vector as "say nothing", which is the safe demo behaviour.
    assert len(embed_face("bm90IGFuIGltYWdl")) == 0;
}


# ------------------------------------------------------------- graph shape

test "Seed populates an empty graph" {
    root spawn Seed();
    people = [root -->[?:Person]];
    assert len(people) >= 3;

    named: list[str] = [];
    for p in people {
        named.append(p.name);
    }
    assert "Sarah Chen" in named;
    assert "Marcus Webb" in named;
    assert "Priya Raman" in named;
}

test "Seed is idempotent - pressing it twice does not fork every person" {
    # The bug this exists for: Seed created unconditionally, so the deployed
    # graph ended up holding Sarah Chen twice, Marcus Webb twice, and four
    # things. A demo button must survive being pressed twice.
    root spawn Seed();
    before = len([root -->[?:Person]]);
    root spawn Seed();
    root spawn Seed();
    assert len([root -->[?:Person]]) == before;
}

test "seeded people carry the context the cards are built from" {
    root spawn Seed();
    for p in [root -->[?:Person]] {
        if p.name == "Marcus Webb" {
            assert p.org == "Northwind";
            assert p.role != "";
            assert p.last_interaction != "";
        }
    }
}

test "Knows edges carry the weights Recognize scores with" {
    root spawn Seed();
    edges = [edge root ->:Knows:->];
    assert len(edges) >= 3;
    for e in edges {
        assert e.closeness >= 0.0 and e.closeness <= 1.0;
        assert e.recency >= 0.0 and e.recency <= 1.0;
    }
}

test "Person defaults are safe to read before anything is enrolled" {
    p = Person(name="Blank Slate");
    assert p.face_vec == [];
    assert p.photo_b64 == "";
    assert p.interests == [];
    assert p.followups == [];
    assert p.org == "";
}


# --------------------------------------------------------- the enrol join

test "Enroll reports a miss when no face is present, and stores nothing" {
    got = root spawn Enroll(name="Faceless", frame_b64="bm90IGFuIGltYWdl");
    assert len(got.reports) == 1;
    assert got.reports[0]["enrolled"] == False;

    for p in [root -->[?:Person]] {
        assert p.name != "Faceless";
    }
}

test "Roster exposes photo_b64 so clients can render a face" {
    root spawn Seed();
    got = root spawn Roster();
    assert len(got.reports) == 1;
    people: list = got.reports[0]["people"];
    assert len(people) > 0;
    for p in people {
        assert "photo_b64" in p;
        assert "enrolled_face" in p;
    }
}


# ------------------------------------------------------------- traversal

test "recall reports not-found rather than inventing a person" {
    got = root spawn recall(name="Nobody Ever Met This Person");
    assert len(got.reports) == 1;
    assert got.reports[0]["found"] == False;
}

test "query returns no matches on an empty question rather than guessing" {
    got = root spawn query(question="");
    assert len(got.reports) == 1;
    assert len(got.reports[0]["matches"]) == 0;
}

test "get_graph emits nodes and links the dashboard can draw" {
    root spawn Seed();
    got = root spawn get_graph();
    assert len(got.reports) == 1;
    payload = got.reports[0];
    nodes: list = payload["nodes"];
    links: list = payload["links"];
    assert len(nodes) > 0;

    for n in nodes {
        assert "id" in n and "label" in n and "kind" in n;
    }
    for l in links {
        assert "source" in l and "target" in l;
    }
}

test "get_timeline is ordered oldest first" {
    got = root spawn get_timeline();
    events: list = got.reports[0]["events"];
    previous: str = "";
    for e in events {
        assert e["ts"] >= previous;
        previous = str(e["ts"]);
    }
}


# --------------------------------------------------------------- captions

test "caption returns empty for empty input and never calls a model" {
    got = root spawn caption(text="   ", lang="en");
    assert got.reports[0]["display_text"] == "";
}

test "caption tidies a short fragment deterministically" {
    # Short fragments used to reach the LLM, which answered with the
    # parameter's own sem text ("A raw chunk of speech-to-text from a noisy
    # room...") and put it on the glasses. Under three words never goes to a
    # model, so this is exact rather than approximate.
    assert (root spawn caption(text="hello", lang="en")).reports[0]["display_text"] == "Hello.";
    assert (root spawn caption(text="test", lang="en")).reports[0]["display_text"] == "Test.";
    assert (root spawn caption(text="ok", lang="en")).reports[0]["display_text"] == "Ok.";
}

test "caption keeps punctuation a fragment already has" {
    assert (root spawn caption(text="hello!", lang="en")).reports[0]["display_text"] == "Hello!";
}

test "caption never leaks prompt text into a caption" {
    # The failure this guards: the model echoing a sem description into the
    # display. Any caption containing prompt vocabulary is a bug, whichever
    # path produced it.
    leaks: list[str] = ["captured speech", "speech-to-text from a noisy", "I need actual input", "provide the"];
    for probe in ["hello", "ok", "hey there"] {
        shown = (root spawn caption(text=probe, lang="en")).reports[0]["display_text"];
        for bad in leaks {
            assert bad.lower() not in shown.lower(), f"caption leaked prompt text for {probe!r}: {shown!r}";
        }
    }
}


# ------------------------------------------------------------ forgetting

test "forget removes a person and their interactions" {
    root spawn Seed();
    doomed = root +>:Knows():+> Person(name="Temporary Contact");
    doomed +>:Had(at="2026-01-01 00:00:00"):+> Interaction(
        timestamp="2026-01-01 00:00:00", summary="a chat", kind="conversation"
    );

    present: bool = False;
    for p in [root -->[?:Person]] {
        if p.name == "Temporary Contact" {
            present = True;
        }
    }
    assert present;

    got = root spawn forget(name="Temporary Contact");
    assert got.reports[0]["forgotten"] >= 1;

    for p in [root -->[?:Person]] {
        assert p.name != "Temporary Contact";
    }
}

test "forget on an unknown name removes nothing" {
    root spawn Seed();
    before = len([root -->[?:Person]]);
    got = root spawn forget(name="Never Existed");
    assert got.reports[0]["forgotten"] == 0;
    assert len([root -->[?:Person]]) == before;
}
