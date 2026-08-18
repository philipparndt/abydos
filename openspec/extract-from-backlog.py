#!/usr/bin/env python3
"""Regenerate openspec/specs/ from .abydos/backlog/spec/.

The backlog spec is the account of the program that stays, and `abydos-backlog
done` folds each item's delta into it. Hand-copying it into openspec/specs/ would
make a second copy that drifts, and the drift would be invisible — which is the
thing this repository warns about oftener than any other. So this is a generator
and openspec/specs/ is its output: delete it and run this and it comes back.

Two differences between the formats have to be crossed, and only two:

  * Heading depth. The backlog spec uses `## Requirement:` and `### Scenario:`;
    OpenSpec wants them one level deeper, under a `## Requirements` heading, with
    a `## Purpose` section above.

  * Normative voice. OpenSpec's validator rejects a requirement whose body has no
    SHALL or MUST in its first line. The backlog spec is deliberately present
    tense — "prose saying what is true, in the present tense, about the program as
    it is now" — and rewriting 6,300 lines of it to please a validator would be
    the tail wagging the dog. So the normative sentence for each requirement lives
    in normative.json and is inserted above the prose, which is copied verbatim.

A requirement in the backlog spec with no entry in normative.json is reported by
name and its file is still written, so the failure is a message rather than a
silent omission.
"""

import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / ".abydos" / "backlog" / "spec"
TARGET = ROOT / "openspec" / "specs"
DATA = ROOT / "openspec" / "normative.json"

REQUIREMENT = re.compile(r"^## Requirement: (.+)$", re.MULTILINE)


def convert(text, capability, statements, purposes, missing):
	lines = text.split("\n")
	title = lines[0] if lines and lines[0].startswith("# ") else f"# {capability}"

	first = REQUIREMENT.search(text)
	if first is None:
		raise SystemExit(f"{capability}: no requirements found")

	# Whatever sits between the title and the first requirement is the file's own
	# paragraph about what this part of the program is, which is exactly what
	# Purpose wants. Five of the files never had one; those are in normative.json.
	intro = "\n".join(lines[1:]).split("\n## Requirement:")[0].strip()
	purpose = intro or purposes.get(capability, "").strip()
	if not purpose:
		missing.append(f"{capability}: no Purpose, and none in normative.json")
		purpose = f"{capability}."

	body = text[first.start():]
	out = []
	for block in re.split(r"(?m)^(?=## Requirement: )", body):
		if not block.strip():
			continue
		name = REQUIREMENT.match(block).group(1)
		rest = block.split("\n", 1)[1] if "\n" in block else ""
		statement = statements.get(name)
		if statement is None:
			missing.append(f"{capability}: no normative statement for {name!r}")
			statement = "TODO: this requirement has no normative statement."
		rest = rest.replace("\n### Scenario:", "\n#### Scenario:")
		out.append(f"### Requirement: {name}\n\n{statement}\n{rest.rstrip()}\n")

	return f"{title}\n\n## Purpose\n\n{purpose}\n\n## Requirements\n\n" + "\n".join(out)


def main():
	data = json.loads(DATA.read_text())
	statements, purposes = data["statements"], data["purposes"]
	missing = []

	if TARGET.exists():
		shutil.rmtree(TARGET)
	TARGET.mkdir(parents=True)

	written = 0
	for source in sorted(SOURCE.glob("*.md")):
		if source.name == "README.md":
			continue
		capability = source.stem
		converted = convert(source.read_text(), capability, statements, purposes, missing)
		directory = TARGET / capability
		directory.mkdir()
		(directory / "spec.md").write_text(converted)
		written += 1

	print(f"wrote {written} capabilities to {TARGET.relative_to(ROOT)}")

	unused = set(statements) - {
		m.group(1)
		for source in SOURCE.glob("*.md")
		for m in REQUIREMENT.finditer(source.read_text())
	}
	for name in sorted(unused):
		print(f"unused statement, requirement is gone from the backlog spec: {name!r}")

	for line in missing:
		print(line, file=sys.stderr)
	return 1 if missing else 0


if __name__ == "__main__":
	sys.exit(main())
