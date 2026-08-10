import Foundation

/// What an assistant is told about this backlog.
///
/// One document, in the backlog itself, and every tool's own file is four lines
/// pointing at it. The reason is the one every other "named once" comment in
/// this repository gives: five copies of a workflow is five workflows within a
/// month, and the one that is wrong is always the one the tool somebody is
/// using happens to read.
public enum BacklogInstructions {
	/// The markers a shared file keeps our part between.
	///
	/// `AGENTS.md` and `copilot-instructions.md` belong to the project, not to
	/// this tool: somebody has written about their build in them and re-running
	/// `init` must not throw that away. So the section is fenced, and a second
	/// run replaces what is between the fences and nothing else.
	public static let startMarker = "<!-- abydos-backlog:start -->"
	public static let endMarker = "<!-- abydos-backlog:end -->"

	/// The whole of it: `.abydos/backlog/AGENTS.md`.
	public static func canonical(projectName: String) -> String {
		"""
		# The backlog of \(projectName)

		Everything left to do lives in `.abydos/backlog/`, as files. There is no
		database and no server: the state of an item is the folder it is in, its
		history is `git log`, and every tool that works this backlog — the app,
		the command line, you — is reading and moving the same files.

		Read this before your first move. The commands below are
		`abydos-backlog`, which is installed with the app; everything it does
		you could also do with `mv` and an editor, and knowing that is the point
		— nothing here is locked behind the tool.

		## The layout

		    .abydos/backlog/
		      AGENTS.md          this file
		      project.md         what this project is, for somebody who has never seen it
		      config.json        which assistants work this backlog
		      spec/              what the project does today, one file per capability
		      open/              written down, not yet agreed
		      ready/             agreed — anybody, or any agent, may start
		      in-progress/       being worked on now
		      waiting/           stuck on something that is not work
		      completed/         done, keeping its number
		      history/           the commit log from before the backlog. Never added to.

		## An item

		Either one file:

		    open/0443-the-capsule-is-clipped-at-a-large-zoom.md

		or a folder, when it carries something a file cannot hold:

		    open/0443-the-capsule-is-clipped-at-a-large-zoom/
		      task.md            the item itself — the same markdown either way
		      images/            screenshots, recordings, a log somebody saved
		      spec/              what this change does to the global spec

		Both shapes are read the same way, so use whichever fits: a task that is
		only words stays one file. `abydos-backlog attach <number> <file>` turns
		a file into a folder and puts the file in `images/`, so you never have
		to convert one by hand.

		The number is given once, when the item is written, and never changes
		again. Moving an item between states moves its file or its folder and
		takes the number with it.

		### What an item says

		A title as the first heading, then what is wrong or what is missing,
		written for somebody who has not been looking at this all week. Then, and
		this is the part that makes the backlog worth more than a list of titles:

		- **Ruled out** — what has already been tried and did not work, and why.
		  Several items here have most of a day of searching in them. The point
		  is that the next person does not repeat it.
		- **Steps** — the work as a checklist, in the order it happens.

		### The checklist

		`## Steps` is how anybody looking at this item — a person, the board in
		the app, the next agent to touch it — can tell what is done and what is
		still missing. It is the one part of an item that is *not* a description
		written once. Keep it current:

		    ## Steps

		    - [x] Find where the pane's width comes from
		    - [x] Ask tmux instead of the window
		    - [ ] A test that fails with the old answer
		    - [ ] Write down here what was ruled out on the way
		    - [ ] `spec/terminal.md` says what the project now does

		The rules are short, and all of them exist because the opposite has
		happened:

		- **Tick it when it is done, in the same change that does it.** Not at
		  the end from memory — a checklist reconstructed afterwards is a
		  summary, and a summary of your own work is always finished.
		- **Never tick ahead.** A `[x]` means somebody could go and look at it
		  now. An item that says four of five with nothing to show for any of
		  them is worse than an item that says nothing.
		- **Add steps as you find them.** Work that turns out to be needed goes
		  on the list, even though it makes the fraction go backwards. That is
		  the number being honest, which is the only reason to have it.
		- **A step is something you can tell you have finished.** "Fix the
		  terminal" is not one. "Ask tmux for the pane width" is.
		- **Do not delete a step you decided against.** Tick nothing, and say
		  underneath why it is not being done — that is a thing the next person
		  needs to know, and a deleted line tells them nothing.

		One list, not two. An item used to carry a plan and a separate list of
		what would make it done, and by the end the two always disagreed.

		The last two steps are on every item: what you ruled out on the way, and
		the spec. Both are below.

		## The spec

		`spec/` says what the project does *today*, one file per capability, as
		requirements:

		    ## Requirement: A pane keeps its ligatures when another is focused

		    Prose, and then the cases that show it.

		    ### Scenario: two panes, the second focused

		    - **Given** two panes showing the same file
		    - **When** the second is focused
		    - **Then** the first still draws `!=` as one glyph

		A backlog forgets. A finished item is a paragraph about a day in March,
		and once enough of them are in `completed/` the only remaining account
		of what the program does is the program. The spec is the other account:
		the thing somebody can read in an afternoon, and the thing to hand an
		agent before it starts.

		Keeping it true is a step of doing the work, not a tidy-up afterwards.
		So an item that changes behaviour carries a **delta** — `spec/<capability>.md`
		inside the item's folder — naming what it changes with one of three
		verbs:

		    ## ADDED Requirement: Images scale inside tmux

		    …the requirement, written as it will read in the spec.

		    ## MODIFIED Requirement: A pane keeps its ligatures when another is focused

		    …the whole requirement as it will now read, not a description of the edit.

		    ## REMOVED Requirement: The old thing

		    …one line on why it is gone.

		Three verbs and not four: a rename is a `REMOVED` and an `ADDED`. A rule
		that only moves the heading would quietly keep the old sentence under the
		new name, which is exactly the drift the spec exists to prevent.

		    abydos-backlog spec add <number> <capability>

		starts one. It makes the item a folder if it is not one yet, and puts the
		names of the requirements already in that capability at the top of the
		file — a `MODIFIED` has to name one of them exactly, and getting that
		wrong is the commonest way a delta fails to fold.

		`abydos-backlog spec check <number>` says whether the delta still fits
		the spec — a `MODIFIED` for a requirement nobody can find means the spec
		moved since the item was written, and that is worth knowing before you
		start rather than at the end.

		## Filing something new

		    abydos-backlog new "The capsule is clipped at a large zoom"
		    abydos-backlog new "…" --files      # a folder, for a screenshot

		It lands in `open/` with the next number and a template. Fill it in. If
		you have a screenshot, `abydos-backlog attach <number> <path>`.

		New items go to `open/`, not to `ready/`. `ready` is a promise that the
		deciding is done, and it is not yours to make on your own behalf.

		## Picking up a ready item

		This is the loop. Do it in this order.

		1.  `abydos-backlog next` — the lowest-numbered item in `ready/`, or
		    nothing. Nothing means there is nothing to pick up; do not go
		    looking in `open/`.
		2.  Read `project.md` and the parts of `spec/` the item touches. Then
		    read the item, all of it, including what has been ruled out.
		3.  `abydos-backlog start <number>` — makes a worktree of its own on
		    branch `backlog/<number>-<slug>`, and moves the item to
		    `in-progress/`. Work there and nowhere else: another agent may be
		    doing the same thing to another item in the same repository, and
		    two of you in one working tree is one of you losing.
		4.  Fill in `## Steps` before you start, if it is thin. You have just read
		    the item and the spec, and this is the only moment you know what the
		    work is and have not started it yet.
		5.  Do the work. Commit as you go, small commits, in that worktree, and
		    **tick each step in the commit that finishes it**. `abydos-backlog
		    show <number>` prints the list back with the fraction, and the board
		    in the app shows the same number on the card — so somebody watching
		    can tell what is done and what is still missing without asking.
		6.  Write the spec delta — `spec/<capability>.md` in the item's folder —
		    if the behaviour changed. `abydos-backlog attach` if there is
		    something to show.
		7.  Write into the item what you found: what you ruled out on the way,
		    what surprised you. This is what makes it worth reading later.
		8.  `abydos-backlog done <number>` — folds the delta into `spec/` and
		    moves the item to `completed/`. It will refuse nothing and tell you
		    everything: any part of the delta that would not fold is printed,
		    and you fix it and run it again.
		9.  Push the branch. Do not merge it yourself unless you were asked to.

		A step still unticked at 9 is either work you did not do — say so in the
		item and leave it unticked — or a step you finished and forgot to mark.
		Do not tick the second kind on the way past without checking which it is.

		The move to `completed/` is on your branch, so until it lands the project's
		own copy of the item stays in `in-progress/`. That is not a mistake to go
		and fix by hand: the item is finished when the work is, and the work is in
		a branch nobody has taken yet.

		If you get stuck on something that is not work — a crash that will not
		happen again, an answer somebody else has to give — move the item to
		`waiting/` and write in it what it is waiting *for*, so it is obvious
		when the wait is over.

		## What not to do

		- Do not renumber anything. A commit message from last year cites these
		  numbers.
		- Do not add to `history/`. It is the commit log from before the backlog
		  and it stops where it stops.
		- Do not move something into `ready/` to give yourself work.
		- Do not rewrite an item you did not do. What it says is what somebody
		  knew at the time, and that is its value.
		- Do not fold a delta into `spec/` before the work is done and committed.
		  The spec says what the project *does*, and a requirement in it that
		  nothing implements is worse than no requirement at all.
		"""
	}

	/// The short form, under a heading, for a file somebody else also writes in.
	public static func pointer(projectName: String) -> String {
		"## The backlog\n\n" + pointerBody(projectName: projectName)
	}

	/// The same words with no heading, for a file that is only this — a skill,
	/// a rule — where the heading is in the frontmatter above.
	///
	/// Two entry points over one string rather than one string a caller takes
	/// the first two lines off, which is what this was: `dropFirst(2)` over the
	/// split lines removed the heading *and* the first sentence, and rejoining
	/// them lost every blank line, so the skill file shipped as one paragraph
	/// of run-together markdown.
	///
	/// Deliberately not a summary of the workflow. A summary is a second copy
	/// that drifts; this says where the workflow is and the few things somebody
	/// has to know before they can go and read it.
	public static func pointerBody(projectName: String) -> String {
		"""
		\(projectName) keeps everything left to do in `.abydos/backlog/`, as
		files: the state of an item is the folder it is in, and its history is
		`git log`.

		**Read `.abydos/backlog/AGENTS.md` before touching any of it.** It is one
		page and it is the whole of the workflow — how an item is shaped, how the
		global spec under `.abydos/backlog/spec/` is kept true as part of doing
		the work, and the order to pick up a `ready/` item in.

		The four things worth knowing before you get there:

		- `abydos-backlog next` is how you find something to do. Only `ready/`
		  counts; `open/` is a pile.
		- Work happens in a worktree of its own, which `abydos-backlog start
		  <number>` makes for you.
		- Every item carries a `## Steps` checklist, and it is how anybody else
		  can tell what is done and what is still missing. Tick a `[ ]` to `[x]`
		  in the same commit that finishes it, never ahead, and add steps you
		  find rather than doing unlisted work.
		- An item that changes behaviour is not finished until the spec says so.
		  `abydos-backlog done <number>` does that fold and will tell you what
		  would not go.
		"""
	}

	/// `project.md`, which `init` writes once and then leaves alone.
	///
	/// Questions rather than blanks: an empty heading gets an empty answer, and
	/// what this file is for is the context nobody thinks to write down because
	/// everybody working on the project already has it.
	public static func projectTemplate(projectName: String) -> String {
		"""
		# \(projectName)

		What this is, for somebody — or something — that has never seen it. Kept
		short enough to be read before every piece of work, which means a page.

		## What it is

		One paragraph. What does this program do, and for whom?

		## How it is built and run

		The commands. How to build it, how to run the tests, how to run it for
		real. Anything that has to be installed first.

		## How it is laid out

		The two or three directories that matter and what lives in each. Not a
		tree — the parts somebody would otherwise have to find out by reading.

		## What the code is like

		The conventions that are not obvious from a random file: how errors are
		handled, what gets a test, what the comments are for, how things are
		named. If there is a house style, this is where it is written down.

		## What not to do here

		The decisions that have already been made and are not up for reopening,
		and the things that look like an improvement and are not.
		"""
	}

	/// The `README.md` a fresh backlog gets.
	public static func readme() -> String {
		var text = """
		# Backlog

		One item per file — or per folder, when it carries a screenshot — in the
		folder that says where it stands. Moving something along is moving its
		file.

		Committed, unlike the rest of `.abydos`: what is left to do belongs to
		whoever is working on the project rather than to one machine.

		The workflow, and what an item and the spec are shaped like, is in
		[AGENTS.md](AGENTS.md). This file is the map.

		## The folders


		"""
		for state in BacklogState.allCases {
			text += "**`\(state.directoryName)/`** — \(state.summary)\n\n"
		}
		text += """
		## spec/

		What the project does today, one file per capability. The backlog says
		what to do and then forgets; the spec is the account that stays. An item
		that changes behaviour carries a delta, and folding that delta in is a
		step of the work rather than a tidy-up afterwards.

		## Numbers

		One sequence across the whole backlog. A number is given once, when the
		item is written, and never changes again — finishing an item moves its
		file and takes its number with it.

		"""
		return text
	}
}
