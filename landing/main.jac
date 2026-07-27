"""recall landing page: a client-only Jac app, no backend.

The whole page is one `cl` component tree. Styling lives in styles.css,
imported once here as an app-wide stylesheet rather than a scoped
.style.css annex, since these rules target the document itself.
"""

import "./styles.css";

# Sections still waiting to be revealed. Mutated in place so the module-level
# binding never has to be reassigned from inside a function.
glob pending: list[any] = [];


def sweep {
    # Reveal every section at or above the trigger line.
    #
    # Sweeping by position rather than reacting to an observer means sections the
    # viewport jumps clean over (End key, scrollbar drag, a fast flick) still
    # resolve instead of being stranded invisible.
    limit: float = window.innerHeight * 0.92;
    i: int = len(pending) - 1;
    while i >= 0 {
        el: any = pending[i];
        if el.getBoundingClientRect().top < limit {
            el.classList.add("in");
            pending.pop(i);
        }
        i -= 1;
    }
}


cl def:pub app -> JsxElement {
    can with entry {
        document.title = "recall: a memory that arrives before the handshake";
        nodes: any = document.querySelectorAll(".reveal,.stagger");
        i: int = 0;
        while i < len(nodes) {
            pending.append(nodes[i]);
            i += 1;
        }
        # A reader who asked for no motion gets the finished page immediately.
        mq: any = window.matchMedia("(prefers-reduced-motion:reduce)");
        if mq.matches {
            for el in pending {
                el.classList.add("in");
            }
        } else {
            window.addEventListener("scroll", sweep);
            window.addEventListener("resize", sweep);
            sweep();
        }
    }

    return <div>
        <header className="top">
            <div className="wrap"><Wordmark size="mark-nav" /></div>
        </header>

        <main>
            <section className="hero wrap">
                <div className="hero-grid">
                    <div>
                        <p className="eyebrow">JacHacks SF 2026</p>
                        <Wordmark size="hero-mark" />
                        <h1>you already know them. recall knows what you left open.</h1>
                        <p className="lede">
                            Glasses that quietly remember everyone you meet, and whispers
                            the one thing you need at the moment you need it.
                        </p>
                    </div>

                    <figure className="whisper">
                        <div className="head">
                            <span className="dot" aria-hidden="true"></span>
                            <span className="eyebrow">in your ear</span>
                        </div>
                        <p className="line">
                            Sarah Chen, VP Product at Acme. The Series B pricing question
                            is still open.
                        </p>
                        <figcaption className="cap">
                            What recall says when you look up and can't place the face in
                            front of you.
                        </figcaption>
                    </figure>
                </div>
            </section>

            <section className="wrap">
                <Rule label="how it works" />
                <div className="lead-in reveal">
                    <h2>three seconds, and you're never the person who forgot</h2>
                    <p className="note">No phone to pull out, no notes to scroll, no pause in the conversation.</p>
                </div>
                <div className="panels stagger">
                    <Panel n="01" title="you look"
                           body="Your glasses see the person in front of you. The picture is used and thrown away. Nothing from the camera is kept." />
                    <Panel n="02" title="recall remembers"
                           body="It recognises someone you've met before and gathers what passed between you: where they work, what you talked about, what you promised." />
                    <Panel n="03" title="you hear one line"
                           body="A single sentence in your earpiece. Their name, and the one thing worth raising right now." />
                </div>
            </section>

            <section className="wrap">
                <Rule label="use cases" />
                <div className="lead-in reveal">
                    <h2>the rooms where forgetting costs you something</h2>
                    <p className="note">Anywhere the relationship matters more than the meeting.</p>
                </div>
                <div className="panels stagger">
                    <Panel title="raising a round"
                           body="Forty investor meetings in a quarter. Recall knows which partner pushed on churn, who asked for the deck a second time, and who you still owe an answer." />
                    <Panel title="client meetings"
                           body="Walk into the account review already knowing what they complained about last quarter, what you promised to fix, and whether you fixed it." />
                    <Panel title="networking events"
                           body="A dozen introductions an hour. Keep every name, and the reason each one was worth having." />
                    <Panel title="renegotiations"
                           body="The last conversation set the terms. Recall surfaces what was agreed, what was left deliberately vague, and who said it." />
                    <Panel title="recruiting and interviews"
                           body="Fifty candidates in a week. Greet each one by name, and pick up exactly where the last conversation stopped." />
                    <Panel title="conferences and reunions"
                           body="The people you see once a year, whose names arrive four seconds too late. Recall gets there first." />
                </div>
            </section>

            <section className="wrap">
                <Rule label="the memory" />
                <div className="lead-in reveal">
                    <h2>it gets better every time you meet someone</h2>
                    <p className="note">
                        Recall keeps a map of the people in your life and what happened
                        between you. Every conversation adds to it, so the second time you
                        meet someone, it already knows about the first.
                    </p>
                </div>
                <Graph />
                <p className="cap reveal">Violet marks the person in front of you right now.</p>
            </section>

            <section className="wrap">
                <Rule label="what it won't do" />
                <div className="lead-in reveal">
                    <h2>a memory aid you can trust in the room</h2>
                </div>
                <div className="panels stagger">
                    <Panel title="it stays quiet when unsure"
                           body="If recall can't place someone with confidence, it says nothing at all. A wrong name, whispered with certainty, is worse than no name." />
                    <Panel title="it never guesses pronouns"
                           body="Recall uses a person's name, or they, never an assumption drawn from a face. Getting that wrong in a tool for remembering people is its own kind of failure." />
                    <Panel title="nobody joins by accident"
                           body="A person is only remembered after you deliberately add them. Recall never quietly catalogues strangers who walk past you." />
                </div>
            </section>

            <section className="wrap">
                <Rule label="who it's for" />
                <div className="closing reveal">
                    <h2>for everyone in the room, and for people this happens to every day</h2>
                    <div className="lead-in" style={{"margin": "0"}}>
                        <p className="note">
                            At a conference you meet a dozen people in an hour and forget
                            most of it by the evening. Recall gives you those names back.
                        </p>
                        <p className="note">
                            For people living with face-blindness, hearing loss, or early
                            memory loss, that isn't an occasional embarrassment. It's every
                            introduction, every day. Same product, much higher stakes.
                        </p>
                    </div>
                </div>
            </section>
        </main>

        <footer className="wrap">
            <div className="foot reveal">
                <div className="colophon-row">
                    <div className="icon" role="img" aria-label="recall app icon">r</div>
                    <p className="colophon">
                        Built at JacHacks SF 2026. The memory is a Jac graph of people,
                        conversations, and the threads between them.
                    </p>
                </div>
                <nav aria-label="Project links">
                    <a href="https://github.com/arshmeets/ReminiSense">Source on GitHub</a>
                    <a href="https://github.com/jaseci-labs/jac">jaseci-labs/jac</a>
                </nav>
            </div>
        </footer>
    </div>;
}


def Wordmark(size: str) -> JsxElement {
    # The logo. Always lowercase, 'rec' ghosted, never the reverse.
    return <span className={"wordmark " + size} aria-label="recall">
        <span className="g" aria-hidden="true">rec</span>
        <span aria-hidden="true">all</span>
    </span>;
}


def Rule(label: str) -> JsxElement {
    # The section rule, borrowed from the brand book's own page furniture.
    return <div className="rule reveal">
        <span className="eyebrow">{label}</span>
        <Wordmark size="mark-sm" />
    </div>;
}


def Panel(title: str, body: str, n: str = "") -> JsxElement {
    return <div>
        {<span className="n">{n}</span> if n != "" else None}
        <h3>{title}</h3>
        <p>{body}</p>
    </div>;
}


def Graph -> JsxElement {
    # People you have met, and what passed between you. Violet marks the match.
    return <div className="figure reveal">
        <svg viewBox="0 0 700 250" role="img"
             aria-label="A map of people you have met: three people connected to you, with the person in front of you highlighted, linked to two things you discussed with them.">
            <g className="edges" stroke="var(--line)" strokeWidth="1.5" fill="none">
                <path d="M104 125 L248 62" />
                <path d="M104 125 L246 125" />
                <path d="M104 125 L248 188" />
                <path d="M332 125 L458 92" />
                <path d="M332 125 L458 170" />
            </g>
            <g className="n-you">
                <circle cx="72" cy="125" r="27" fill="var(--surface)" stroke="var(--ink)" strokeWidth="1.5" />
                <text x="72" y="130" textAnchor="middle" fontSize="13" fill="var(--ink)">you</text>
            </g>
            <g className="nodes" fontSize="13.5">
                <rect x="248" y="42" width="84" height="40" rx="10" fill="var(--surface)" stroke="var(--line)" strokeWidth="1.5" />
                <text x="290" y="67" textAnchor="middle" fill="var(--muted)">Priya</text>
                <g className="active">
                    <rect x="246" y="103" width="88" height="44" rx="11" fill="var(--surface)" stroke="var(--accent)" strokeWidth="2" />
                    <text x="290" y="130" textAnchor="middle" fill="var(--ink)" fontWeight="600">Sarah</text>
                    <circle cx="334" cy="105" r="5.5" fill="var(--accent)" />
                </g>
                <rect x="248" y="168" width="84" height="40" rx="10" fill="var(--surface)" stroke="var(--line)" strokeWidth="1.5" />
                <text x="290" y="193" textAnchor="middle" fill="var(--muted)">Dan</text>
            </g>
            <g className="cards" fontSize="13" fill="var(--muted)">
                <rect x="458" y="74" width="200" height="36" rx="9" fill="var(--surface)" stroke="var(--line)" strokeWidth="1.5" strokeDasharray="3 3" />
                <text x="474" y="97">Series B pricing, still open</text>
                <rect x="458" y="152" width="200" height="36" rx="9" fill="var(--surface)" stroke="var(--line)" strokeWidth="1.5" strokeDasharray="3 3" />
                <text x="474" y="175">intro to their infra lead, sent</text>
            </g>
        </svg>
    </div>;
}
