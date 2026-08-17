## Context

The rules exist. They have been typed into prompts by hand, repeatedly, by somebody
who already knew them. What does not exist is a place they live where an agent finds
them without being told.

Two constraints shape the answer, and they pull against each other:

- `BacklogRunner.prompt` is thin **on purpose**, and its comment is right: a second
  copy of the workflow would drift invisibly, because nobody reads the prompt a
  button builds. So the rules must not go in the prompt.
- The prompt is nevertheless the only thing that names where an agent should look.
  Whatever is chosen has to be reachable from `AGENTS.md` or `project.md`, or read by
  the assistant on its own.

## Goals / Non-Goals

**Goals:**

- An agent started by `abydos-backlog start` knows these rules without being handed
  them.
- The rules live in one copy.
- What is permanently true and what is true today are visibly separate, and the
  second can be changed without a commit that reads like a policy change.

**Non-Goals:**

- Writing rules for other people's projects. `backlog-spec` is published; these rules
  are Abydos's, and the distinction is why `project.md` is a poor host.
- Enforcing the rules in code. That is worth doing for some of them — 0534 is exactly
  that for "guard every app launch" — but a rule an agent reads and a rule the program
  keeps are different work.
- Covering every assistant equally. `BacklogAssistant` knows about more than one, and
  that is an argument about `CLAUDE.md`, not a requirement to write four files.

## Decisions

**A file of the project's own, pointed at from `project.md`.** Of the four candidates
it is the only one that is one copy, belongs to Abydos rather than to the published
tool, and is reachable by an agent the tool started. `CLAUDE.md` has the real
advantage that it is read without being pointed at — which covers agents nobody
started through the backlog, and that is most of them — so the strongest arrangement
is likely a `CLAUDE.md` that *is* that file, or one that points at it in a line. What
must not happen is two copies; if `CLAUDE.md` exists it either holds the rules or
names the file that does, never repeats them.

**The permanent and today's live in two places, not two sections.** A section heading
is not enough: the temporary half needs to be editable without a commit that reads
like a policy change, and that means a separate file, ignored or not, that says at
the top that it describes today. Mixing them is what teaches an agent to distrust all
of it — and the container-runtime rule is the proof, being a fact about a Tuesday
sitting in a list of things learnt the hard way.

**Each rule keeps the failure that motivated it.** "Never push" is obeyed; "never
push, because an agent once created five public Docker Hub repositories nobody asked
for" is *understood*, and an understood rule generalises to the case the list does
not mention. This is the house style applied to prose rather than code, and it is the
reason the list above is worth more than a checklist.

**Prefer a rule the program keeps.** Where a rule can become a guard, it should
eventually — 0534 does this for guarding app launches, and `NamedSuiteTests` already
does it for `TestDefaults.make()`. The document says which rules are enforced
somewhere, because a rule with a guard behind it is one an agent can stop worrying
about and a rule without one is where the attention belongs.

## Risks / Trade-offs

- **A document nobody reads** → The check is behavioural, not editorial: start a
  throwaway item and see whether the agent knows a rule it was not given in its
  prompt. Anything less is assuming.
- **Drift, which is what the prompt's comment warns about** → One copy, and a review
  step: a rule learnt the hard way goes in the file at the time, not later.
- **The temporary file going stale and being trusted** → It says at the top that it
  describes today and when it was last touched. A stale "Docker is stopped" is worse
  than no file, because it is confidently wrong.
- **`backlog-spec` users inheriting Abydos's rules** → Avoided by keeping them out of
  `project.md`, which is the published tool's file.

## Worth knowing

`start` prints the `cd` and the prompt whenever no agent launches, so working an item
by hand is still a first-class path — and passing `--assistant` a name that is not
installed is currently the way to get that on purpose. If the rules land somewhere an
agent reads, that stops being a workaround and becomes a choice.

## Open Questions

- `CLAUDE.md` holding the rules, or pointing at a file that does? The first is fewer
  hops; the second survives `BacklogAssistant` gaining a second assistant.
- Should the temporary file be committed? Committed, it is visible to every agent and
  its history is readable. Ignored, it can be edited freely. It cannot be both.
