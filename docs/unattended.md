# Unattended development sessions

Run a long build or test command with the Mac and display kept awake:

```sh
bash scripts/unattended.sh swift test
```

Arguments, working directory and the command's exit status are preserved. For
several commands or a pipeline, pass a shell explicitly:

```sh
bash scripts/unattended.sh bash -c 'swift test && swift build -c release'
```

For manual GUI testing, start a bounded session in a terminal:

```sh
bash scripts/unattended.sh /bin/sleep 14400
```

That session expires after four hours; press Control-C to end it sooner. The
helper uses macOS `caffeinate -di` and releases its keep-awake assertions when
the command finishes. `pmset -g assertions` shows the active display and system
idle-sleep assertions. It fails before starting the command if `caffeinate` or
the requested executable is unavailable.

Start while the Mac is unlocked and connected to power. The helper prevents
idle sleep during the command; it does not unlock a Mac, override an explicit
lock, or change password, screensaver, power or security preferences. A restart
ends the session. Launch background jobs through a foreground command that
waits for them, so the keep-awake session covers their whole lifetime.

This helper and guide are mirrored in the Workbench Voice and StageMark repos.
