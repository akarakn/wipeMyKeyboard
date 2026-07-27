# W.I.P.E. My Keyboard

*Workplace Input Prank Eliminator*

**Lock the input, not the screen.**

A lightweight macOS utility that temporarily disables selected keyboard, mouse,
and trackpad input without locking your screen. Keep curious coworkers away
from your workstation, or safely wipe your devices clean. It supports automatic
or infinite lock durations, a global shortcut, and command-line control.

> Clean your keyboard without accidentally resigning.

I made it for myself but sharing is caring! :)

## Command-line control

The app bundle includes a CLI helper that controls the running menu bar app:

```sh
wipemykeyboard --lock
wipemykeyboard --unlock
wipemykeyboard --status
```

Install the app under `/Applications`, then expose the helper on your `PATH`:

```sh
sudo ./install-cli.sh /Applications/wipeMyKeyboard.app
```

For a local development build:

```sh
./wipeMyKeyboard.app/Contents/Helpers/wipemykeyboard --status
```

The menu bar app must be running. SSH control works when the SSH session uses
the same macOS user account that is running the app. Run the CLI as that user,
not with `sudo`.
