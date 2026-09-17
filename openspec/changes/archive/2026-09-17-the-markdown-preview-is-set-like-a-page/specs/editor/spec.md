# Editor

## ADDED Requirements

### Requirement: TypeScript is coloured as JavaScript plus its own additions

TypeScript SHALL be coloured as JavaScript plus its own additions: a `.ts` or
`.tsx` file, and a `ts` or `tsx` fence in a markdown preview, are coloured by
the JavaScript highlight queries followed by the TypeScript grammar's own, compiled together against the TypeScript grammar.
Keywords, strings, calls and comments SHALL be coloured as they are in
JavaScript; types and type parameters SHALL be coloured as the TypeScript
queries say. A joined query that fails to compile SHALL be a red test, not a
file quietly left in one colour.

Reported 2026-09-17 with a screenshot: in a `ts` fence, `await`, `async`, the
strings and every call name were the body colour, and only the one identifier
beginning with a capital was coloured. The grammar's own `highlights.scm` is
thirty-five lines of type patterns and expects to inherit the JavaScript ones.

#### Scenario: a Playwright snippet

- **GIVEN** `await cast.type(page.locator('input[name="email"]'), USER)` in a
  `.ts` file
- **WHEN** it is coloured
- **THEN** `await` is a keyword, the quoted string is a string, `type` and
  `locator` are calls, and `USER` is a constant

#### Scenario: the same in a fence

- **GIVEN** the same line inside a ```` ```ts ```` fence in a markdown document
- **WHEN** the preview is shown
- **THEN** it carries the same colours the editor gives the file

#### Scenario: a grammar bump that renames a node

- **GIVEN** a TypeScript grammar in which a node the JavaScript query names no
  longer exists
- **WHEN** the test suite runs
- **THEN** the test that compiles the joined query fails and names the pattern
