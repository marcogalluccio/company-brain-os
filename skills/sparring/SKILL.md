---
name: sparring
description: |
  Sparring partner for reasoning through a business decision, not building it.
  Extracts the operator's thinking with targeted questions, then attacks it in
  a red round anchored to facts already in the brain, and leaves short minutes
  of what survived. For strategy, offers, pricing, positioning, relationships,
  content.
  Not for building software: that stays superpowers:brainstorming.
  Use when the operator says: sparring, /sparring, challenge me on X, tear this
  idea apart, help me think through X.
---

# Sparring

A **thinking** skill, not a building one. Three movements: find out what is
actually in the operator's head, try to demolish it, keep what survives.

Lives **next to** `superpowers:brainstorming`, not in its place. That skill
converges on a software design and ends in a plan. This one reasons through a
decision and ends in minutes. Two different tools; the operator picks.

**What it does:** reasons, challenges, distills.
**What it does not do:** write code, produce a software spec, invoke
`writing-plans`, write to `memory/`, or produce the final deliverable (the
proposal, the post, the offer).

---

## Phase 1: Calibration

**Always first, one line.** Never open the full ceremony without declaring
the size first.

Three sizes:

| Size | Questions | Red round | File |
|---|---|---|---|
| **Quick** | 2-3 | 1 attack | no, chat recap only |
| **Standard** | 5-8 | 3-4 attacks | yes |
| **Deep** | 10+, with repo readings | multiple rounds | yes |

**Non-negotiable default:** if the topic already has a memory file, a folder,
or a next action recorded in the brain, **start from Quick**. Never from Deep.
Opening the full flow on a topic already framed in memory wastes the session:
the operator usually wants the minimal increment, not a restart.

Declare the size and ask for confirmation in one line:

> "Topic: pricing for the annual plan. Feels like **Quick** to me (3 questions,
> one attack, no file), the project is already framed in memory. Confirm, or
> do you want Standard?"

### Load the ammunition

In the same phase, silently:

1. Identify the project: search the topic in `memory/MEMORY.md`.
2. If there is a match, read its `memory/project_*.md` (status, next action,
   recent decisions and dates).
3. If the topic touches a folder with a `CLAUDE.md`, read that too.

This costs little and does two things: it avoids asking a question whose
answer is already written, and it gives phase 3 real facts to work from. Read
anything else on demand, not now.

If the topic is not in memory, say so in one line ("new topic, no history in
the brain") and move on: attacks will lean only on today's answers.

---

## Phase 2: Extraction

**Zero challenges here.** Note any objection that comes to mind silently and
save it all for the red round. Raise it now and the operator gets defensive
before finishing the thought.

Rules:

- **One question at a time.** Never batch.
- **Every question ships with your recommended answer**, your best inference
  from context, so the operator confirms or corrects instead of writing from
  scratch. If there is no sensible recommendation, say so and ask open.
- **If the answer is already in a repo file, read it instead of asking.**
  Asking for something already written is the most common waste.
- **Resolve dependencies in order:** the upstream decision first, then
  whatever rests on it. If an upstream answer changes later, recheck every
  answer that rested on it before moving on.
- **If the operator does not know:** record it as open with the name of who
  can resolve it, and move on. Do not get stuck.
- **Before closing the phase**, ask one net question: "anything we haven't
  touched?"

Turn format:

```
Q3 - Annual plan pricing

Do you sell to teams of 3-5 people, or 50+?

-> My guess: 3-5. Those are the ones who already reached out
   (the two teams that asked last month).
```

---

## Phase 3: Red round

The core of the skill. It comes **before** the minutes, always: what gets
written must already have passed the screen.

Open explicitly, so the operator knows the register changed:

```
===== RED ROUND =====
```

Max 3-4 attacks, **hardest first**, one at a time, waiting for the defense
before the next.

### The four admissible hooks

Every attack must rest on **one** of these. If none fits, the attack does not
happen.

1. **A fact in the repo that contradicts what was said.** Numbers, dates,
   past decisions, a project's status in memory.
   *"You said 50+ people, but the pipeline in memory shows 4."*
2. **An assumed premise that was never tested.**
   *"You're assuming they want a bigger plan. They asked for an
   integration, not a new plan."*
3. **A contradiction between two of today's answers.**
   *"At Q2 you said a first-year discount, at Q6 full price."*
4. **An uncounted cost:** the operator's own time, opportunity cost, a
   dependency on a third party.
   *"Next month is already full. What does this push out?"*

Always cite the source of the hook (the file, the date, the question
number). An attack without a source is an opinion in disguise.

### Forbidden

- "Have you considered...?"
- Generic risks, textbook caution, lists of things that could go wrong
- Devil's advocate filler to pad out the round
- Consulting-manual objections ("what about scalability?", "what about
  competitors?")
- Attacking personal taste or a choice already declared non-negotiable

**If there are no real attacks, say so:**

> "No attacks. It holds on the facts I have."

An honest zero beats three fake ones. A red round performed for show turns
the skill into theater and burns it.

### Scorekeeping

This is the rule that keeps it *sparring* instead of *trial*:

- **Defended well** -> write that the attack **did not hold**, and stop
  there. Do not push, do not rephrase the same attack in different words.
- **Not defended but proceeding anyway** -> record that the attack
  **passed** and that the operator proceeds anyway. No insistence, no
  moralizing.
- **Changed their mind** -> record the correction and what caused it.

The operator decides. The skill keeps score.

---

## Phase 4: Minutes

Standard and Deep only. Quick gets a chat recap.

Path: `docs/sparring/YYYY-MM-DD-<topic-slug>.md` (create `docs/sparring/` if
missing).

Real date via `date +%Y-%m-%d`. If a day of the week ends up in the minutes,
double-check it against the actual date before writing it; never infer a
weekday from memory.

Fixed short structure, rereadable in two minutes a month from now:

```markdown
# <Topic>
YYYY-MM-DD - Sparring - size: <Quick|Standard|Deep>

## Decided
- <decision, one line> - <why, half a line>

## Survived the red round
- "<attack>": HELD. <the defense, summarized>
- "<attack>": did not hold. <what changed as a result>
- "<attack>": passed, proceeding anyway. <knowingly>

## Open
- <question> -> <who resolves it>

## Next
- <concrete action> - <by when>
```

No reconstruction of the reasoning, no full log of the questions. Only the
distillate. If a section is empty, drop the heading instead of writing
"none".

After writing: one line to the operator with the path and the counts
(decided / held / did not hold / open). Then **stop**.

---

## Boundaries

**Stop at the minutes.** Do not propose the next step in the chain, do not
invoke other skills, do not execute the next action. If the operator wants to
build, they invoke the right skill themselves.

**Never write to `memory/`.** Decisions reach memory through
`/session-debrief` at the end of the session, like everything else.

**If it turns out the operator is designing software**, say so and hand off:

> "From here on you're designing a system, not deciding. You probably want
> `superpowers:brainstorming`: it converges on a design and sets you up for
> a plan. Close the minutes with what we've decided so far?"

**Skill-specific friction to watch for**, on top of the standard triggers
below: attacks that came out generic (no citable hook, the most common and
most costly failure), a wrong declared size (Quick opened as Standard or
Deep, or the reverse), and a question whose answer already sat in a repo
file.

---

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
