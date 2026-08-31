# Git refs tree — delta

## ADDED Requirements

### Requirement: Tags are newest first

The TAGS section SHALL order its tags by creation date, newest first, by
default. The date is the tag's own for an annotated tag and the pointed-at
commit's for a lightweight one — `creatordate`, which git is already asked
for.

Alphabetical order made the tag somebody just cut findable only by name, and
lied about versions besides: `v1.10` sorted before `v1.9`. The newest-first
order was already fetched on every refresh and thrown away by the shared
name sort.

#### Scenario: the tag just cut is on top

- **GIVEN** a repository whose newest tag is `v2.0` and whose alphabetically
  first tag is `alpha`
- **WHEN** the TAGS section is read
- **THEN** `v2.0` is the first row

#### Scenario: annotated and lightweight tags share one ordering

- **GIVEN** an annotated tag created after a lightweight one
- **WHEN** the TAGS section is read
- **THEN** the annotated tag is above it

### Requirement: A section header offers its sort orders

The context menu of the TAGS section header SHALL offer the sort orders —
newest first, and by name — with a mark on the one in force, and the LOCAL
and each remote section header SHALL offer the same choice. LOCAL and the
remotes default to by name, which is what they show today.

#### Scenario: switching tags to name order

- **GIVEN** the TAGS section in its default order
- **WHEN** "By Name" is chosen from the header's menu
- **THEN** the tags re-sort alphabetically and the menu marks "By Name"

#### Scenario: local branches by date

- **WHEN** "Newest First" is chosen on the LOCAL header
- **THEN** the local branches order by their tips' dates, newest first

#### Scenario: each section keeps its own choice

- **GIVEN** TAGS set to name order
- **WHEN** the LOCAL section is read
- **THEN** LOCAL's order is unchanged by the choice made on TAGS

### Requirement: The order is remembered

Each section kind's choice — local, remotes, tags — SHALL be kept between
sessions. Choosing again every morning is choosing nothing.

#### Scenario: the choice survives a restart

- **GIVEN** TAGS switched to name order
- **WHEN** the app is quit and reopened on the same project
- **THEN** TAGS is in name order and its menu marks "By Name"

### Requirement: The order reaches everything the section shows

The chosen order SHALL apply within each folded prefix level (folders keep
their place before leaves and their own name order — a folder has no date),
SHALL apply to the filtered, flattened list, and the LOCAL section's order
SHALL be the order the titlebar branch pill uses, keeping the rule that two
lists of the same branches in one window do not disagree.

#### Scenario: date order inside a folder

- **GIVEN** local branches `feature/old` and `feature/new`, in date order
- **WHEN** the `feature` folder is opened
- **THEN** `new` is above `old`

#### Scenario: the filtered list obeys the choice

- **GIVEN** TAGS in newest-first order and a filter that matches three tags
- **WHEN** the flattened matches are shown
- **THEN** they are newest first

#### Scenario: the pill agrees with the tree

- **GIVEN** LOCAL switched to newest first
- **WHEN** the titlebar branch pill's list is opened
- **THEN** the branches are in the same order the LOCAL section shows
