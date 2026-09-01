# Editor — delta

## ADDED Requirements

### Requirement: The gutter answers a right-click with its own menu

A right-click on the gutter — the left area holding the line numbers — SHALL
open a menu about the gutter, not the text area's menu, and that menu SHALL
offer toggling blame mode: Show Blame when the column is hidden, Hide Blame
when it is showing. Blame mode is the column beside the lines naming who last
changed each line, loaded when the mode is turned on; the gutter menu, the
View menu and ⌥⌘B toggle one state and never disagree.

"Who changed this line" is asked at the line, and the gutter used to answer a
right-click with Go to Definition and Paste.

#### Scenario: blame from the line numbers

- **GIVEN** a file open in the editor, blame hidden
- **WHEN** the gutter is right-clicked and Show Blame chosen
- **THEN** the blame column appears, exactly as ⌥⌘B would have shown it

#### Scenario: the title tells the state

- **GIVEN** blame showing
- **WHEN** the gutter is right-clicked
- **THEN** the entry reads Hide Blame, and choosing it takes the column away

#### Scenario: the text area keeps its menu

- **WHEN** the text — right of the gutter — is right-clicked
- **THEN** the menu is the text area's menu, unchanged
