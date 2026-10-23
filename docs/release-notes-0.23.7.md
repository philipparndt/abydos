# Abydos 0.23.7

## Boards open on servers that sign in through the company's login

On a vboard server whose login wants a managed device, the board tab showed
"Set up your device to get access" instead of the board. The sign-in now opens
in the system's sign-in window, where the Mac can prove itself, and the token
it brings back is kept in the Keychain, so it is asked for once per server.
*Sign Out* is under Settings ▸ Tools ▸ vboard.

## A board from a file is a session board, and the AI can work on it

A `.vboard` opened as a board is now one of vboard's session boards: listed
nowhere, never made permanent, held by Abydos for as long as the tab is open
and deleted when it closes. It is no longer encrypted, which is what kept the
AI out; the status bar says it is on the server for this session only. Share
links from the board's own share dialog name the server.

## Boards open quickly and look like the editor

A board loads in about the time the page takes, and much faster the second
time, without a white page in between. It follows the editor's zoom and its
light or dark theme, uses the editor's colours instead of vboard's blue, and
the bar below it is gone: where the board is and who is on it is in the status
bar. Closing a board tab no longer freezes the window.
