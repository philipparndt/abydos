## 1. The decision, first

- [x] 1.1 Decide whether the refusal goes entirely or survives on the second
      argument — that a recipe naming a file outside says something surprising —
      and write down which and why.
      **The refusal goes.** Nobody has hit the case, so there is no report to
      keep it alive, and the argument for keeping it was always about what the
      viewer *could* contain rather than about the recipe being odd. A viewer
      that renders a recipe and says nothing about where its `output:` points is
      answering the question it was asked; a recipe naming `../../out.3mf` is
      between whoever wrote it and whoever builds it deliberately, and the
      export path — which does obey `output:` — is where that matters.
      **Ruled out: keeping it with the current wording**, which is the only
      option that is certainly wrong now.
- [x] 1.2 If it survives, its message stops making the claim about containment
      and makes the argument actually being kept. Moot: it does not survive.

## 2. The floor

**Measured first, because the whole change stands on it.** `go3mf 0.16.6` is
what is installed here, and a recipe declaring an absolute `output:` built with
`-o <buildDirectory>/contained.3mf` wrote only to the `-o` path — nothing at all
appeared at the absolute one. So containment can be a property of the command,
and the sentence in the refusal is no longer true.

- [x] 2.1 `go3mf version` is read where `findGo3mfExecutable` already locates the
      binary, and the answer decides whether `-o` may be passed.
- [x] 2.2 An older `go3mf` keeps today's behaviour, refusal included: passing
      `-o` to 0.16.5 writes somewhere else silently, which is worse than the bug.
      Its message says why it refuses now — the tool's age, not a limit on what a
      viewer can contain.
- [x] 2.3 A test over the version comparison, since it is a string from another
      program. `testTheVersionIsReadOutOfWhatTheToolPrints` and
      `testOnlyZeroSixteenSixAndNewerHonourTheFlag`.

## 3. Upstream

- [x] 3.1 In GoSTL: `go3mfRecipeBuildArguments` carries `-o
      <buildDirectory>/<basename>`, its comment loses the paragraph saying it
      must not, and `go3mfRecipeOutputURL`'s nil case goes with them.
      **And a second argument builder stays** for the export path: the `o` key
      builds into the project deliberately and hands the result to a slicer, so
      the declaration is the answer there. One function would have meant one of
      the two paths doing the other's job — which is what the item warned about
      and is easy to miss, since both call sites read the same before the
      change.
- [x] 3.2 Committed there, pushed nowhere from here. `8c35cc9` on
      `abydos/recipe-output`, in a worktree at `~/dev/3d/gostl-recipe-output` —
      a worktree because the checkout at `~/dev/3d/gostl` is parked on
      `abydos/openscad-command` four commits after v0.20.2, and moving somebody
      else's HEAD to do this would be the wrong kind of tidy.
      `Go3mfRecipeTests` 18 of 18. One failure elsewhere in that suite,
      `STLParserTests.testInvalidASCIIFormat`, fails on `main` without this
      change too — stashed and re-run to be sure, and left alone.

## 4. Watched

- [x] 4.1 A recipe with an absolute `output:` previews, and writes only inside
      the build directory. **At GoSTL's level, not through Abydos's pane**: its
      own end-to-end test builds a real recipe through `buildRecipe`, and
      asserts the project is untouched, the declared file is not created, and
      the result is in a build directory of this program's own. Driving it
      through the app would mean putting Abydos's pinned dependency into edit
      mode, which is a separate step and is named below.
- [x] 4.2 One with `../` does the same. Same shape, end to end, with the extra
      assertion that nothing appears two directories up — where the declaration
      pointed.
- [x] 4.3 The export path still writes where the recipe says — the `o` key,
      unchanged. Held by `testExportingStillLetsTheRecipeDecide`, over the
      arguments: no `-o`, so the declaration decides. Not driven through a
      slicer, which nothing here can do.
- [ ] 4.4 An older `go3mf`, refusing as it does today. **Not done**: 0.16.6 is
      what is installed, and the branch is reached only by a tool older than
      that. The floor itself is tested — `testOnlyZeroSixteenSixAndNewerHonourTheFlag`
      — and the refusal it guards is one `guard` away, but nothing here has run
      an old binary to watch it happen.

## 5. Finish

- [x] 5.1 The `previews` capability says what contains a recipe now, and stops
      giving the reason that is no longer true. `.abydos/backlog/spec/previews.md`
      no longer exists — the backlog was dropped in between, and the capability
      under `openspec/specs` is the one copy. The delta carries a `## MODIFIED
      Requirements` section over *Rendering a recipe does not write into the
      project*, because without it the archive would leave two requirements in
      that capability contradicting each other: one refusing an absolute
      `output:`, one containing it. The sentence that goes is "that recipe is not
      rendered rather than rendered somewhere it was not asked to go"; the
      refusal survives only against a tool too old to be told, and the scenario
      now says so.
- [x] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0`, 3035 tests in 398 suites, 2 known issues, load 11.8
      over 10 cores. `make warnings exit=0` — four warnings, all in vendored
      tree-sitter C, and the run's own last line is "No warnings in this
      repository's Swift". The first run of the suite was made through a
      pipeline with a bash-only `${PIPESTATUS[0]}` in a zsh shell, so no status
      came back at all; per the house rule that counts as a failure, and it was
      re-run rather than read off the output.
- [x] 5.3 What was ruled out on the way:

      - **A working directory instead of a flag.** It was the lever the refusal
        was built on, and it cannot contain an absolute path — which is why the
        refusal existed. `-o` can.
      - **Reading the recipe and rewriting its `output:`** before building.
        Rejected: a copy of somebody's recipe with a line changed is a second
        source of truth, and the tool would then be building a file the reader
        never wrote.
      - **Refusing quietly and rendering nothing**, as today. Kept only for a
        tool older than 0.16.6, which ignores the flag; against a newer one
        there is nothing left to refuse.
      - **Matching the tool's message** to find out whether it honoured `-o`.
        Rejected for the reason the preparing-server work gave: a message is one
        program's wording. The version is a fact and is asked for once.
      - **Trusting a local checkout of the dependency** to say what upstream
        does. Ruled out earlier the hard way, in this same session's Cadova
        work: a local checkout of a dependency is a cache, not the upstream.
      - **Driving it through Abydos's preview pane.** Not ruled out, not done:
        it needs this repository's pinned GoSTL put into edit mode against the
        worktree, which changes the build state of the app somebody is using.
        4.1–4.3 are held at GoSTL's own level instead, and 4.4 is not held at
        all.
