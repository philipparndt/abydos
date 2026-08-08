# A language server is looked for where the user's own shell would find it

`25801afc8` · 2026-08-05

`npm install -g typescript-language-server` and the editor still said there was
no server. It was installed; the app could not see it.

The lookup was a PATH this process happened to inherit plus a hardcoded list of
well-known directories. Neither can find anything a version manager installed.
Under fnm the binary lands in

  ~/.local/share/fnm/node-versions/v24.15.0/installation/bin

which no fixed list would guess, and nvm, mise, asdf, pyenv and rbenv each have
a layout of their own. This is the same problem `UserShell` was written for —
its comment names fnm outright — solved for the run console and not here. So
the search now asks the login shell, which is the only source that keeps up.

Symlinks are resolved, and that is the point rather than tidiness. What fnm
actually puts on the PATH is a directory belonging to one shell session,
`~/.local/state/fnm_multishells/53245_1785944432859/bin`, created when that
shell starts. Both forms are kept: the shell's own first, so a shim that
dispatches by version is still invoked as a shim, and the resolved one behind
it for when the session directory is gone.

Worked out once, and warmed at launch off the main thread. The first asker is
the editor opening a file, and a third of a second running somebody's .zshrc
would be a stall on the first file of every session.

The hint was also wrong, and wrong in a way that fails after it appears to
work. `npm install -g typescript-language-server typescript` resolves
typescript to 7.0.2 today. TypeScript 7 is the native compiler and ships no
`lib/tsserver.js`, which is the one file typescript-language-server drives — so
the pair installs cleanly, starts, and refuses the handshake with "Could not
find a valid TypeScript installation". It says `typescript@5` now.

Checked from an environment with PATH=/usr/bin:/bin, which is what a Dock
launch has: the server is found, started, and reaches "initialized".
