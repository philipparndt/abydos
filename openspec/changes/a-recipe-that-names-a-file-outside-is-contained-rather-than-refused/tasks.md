## 1. The decision, first

- [ ] 1.1 Decide whether the refusal goes entirely or survives on the second
      argument — that a recipe naming a file outside says something surprising —
      and write down which and why.
- [ ] 1.2 If it survives, its message stops making the claim about containment
      and makes the argument actually being kept.

## 2. The floor

- [ ] 2.1 `go3mf version` is read where `findGo3mfExecutable` already locates the
      binary, and the answer decides whether `-o` may be passed.
- [ ] 2.2 An older `go3mf` keeps today's behaviour, refusal included: passing
      `-o` to 0.16.5 writes somewhere else silently, which is worse than the bug.
- [ ] 2.3 A test over the version comparison, since it is a string from another
      program.

## 3. Upstream

- [ ] 3.1 In GoSTL: `go3mfRecipeBuildArguments` carries `-o
      <buildDirectory>/<basename>`, its comment loses the paragraph saying it
      must not, and `go3mfRecipeOutputURL`'s nil case goes with them.
- [ ] 3.2 Committed there, pushed nowhere from here.

## 4. Watched

- [ ] 4.1 A recipe with an absolute `output:` previews, and writes only inside
      the build directory.
- [ ] 4.2 One with `../` does the same.
- [ ] 4.3 The export path still writes where the recipe says — the `o` key,
      unchanged.
- [ ] 4.4 An older `go3mf`, refusing as it does today.

## 5. Finish

- [ ] 5.1 `.abydos/backlog/spec/previews.md` and the `previews` capability say
      what contains a recipe now, and stop giving the reason that is no longer
      true.
- [ ] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 5.3 Write down what was ruled out on the way.
