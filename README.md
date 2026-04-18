# Cinnamon Layout Switch On Release

[English](README.md) | [Русский](README_RU.md)

[![License: MIT](https://img.shields.io/github/license/gugglegum/cinnamon-layout-switch-release)](https://github.com/gugglegum/cinnamon-layout-switch-release/blob/master/LICENSE)
[![CI](https://github.com/gugglegum/cinnamon-layout-switch-release/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/gugglegum/cinnamon-layout-switch-release/actions/workflows/ci.yml)

Scripts for Linux systems running the Cinnamon desktop environment that switch the keyboard layout not when `Alt+Shift` or `Ctrl+Shift` is pressed, but when the keys are released.

## What Problem This Solves

In the standard Cinnamon/X11 layout-switching scheme, combinations such as `Alt+Shift` are usually handled by XKB itself. This is inconvenient when the same modifiers are also part of other shortcuts, for example:

- `Alt+Shift+Tab`
- `Alt+Shift` + combined with custom IDE shortcuts
- `Ctrl+Shift` + actions in the terminal, editor, or browser

In older X11/XKB setups, the main problem was a direct conflict with such shortcuts: layout switching fired on key press and could intercept the combination before the application had a chance to handle it.

On Linux Mint 22.3 / Cinnamon 6.6.x, the behavior appears to have changed. The built-in `Alt+Shift` switcher no longer necessarily breaks combinations such as `Alt+Shift+Tab` the way it used to. However, a different practical problem shows up instead: when `Alt+Shift` is tapped quickly, switching can become unreliable. A very short tap may be ignored, while holding the keys slightly longer usually works more reliably.

There is also another observed effect of the built-in `Alt+Shift` behavior in Mint 22.3: during switching, the active window or active input field can briefly lose focus. In many applications the focus is restored automatically, but not in all of them. For example, in `Nemo` and `Firefox` this can be visible as a brief loss of the active input outline, while in `VS Code` or `Mattermost` focus may sometimes fail to return at all.

On Linux Mint 22.3 / Cinnamon 6.6.x there is an additional problem: if you try to switch layouts with external low-level commands outside Cinnamon itself, you can end up with desynchronization between the actual layout state and the panel applet. In practice this looks like:

- text input is already using one layout while the panel flag shows another one;
- switching starts behaving inconsistently;
- the indicator and the real layout state drift apart.

Because of that, this repository is useful not only as a way to move switching to key release, but also as a way to keep switching predictable and stable on modern Cinnamon versions without breaking panel synchronization.

## How It Works

The solution is built around a single listener script: `kb-layout-switch-release.sh`.

This Bash script listens to `xinput test`, tracks modifier key press and release sequences, and on key release asks Cinnamon to perform its own built-in modifier-based layout switch through `gdbus` and `org.Cinnamon.Eval`.

Supported sequences:

- `Alt+Shift`
- `Ctrl+Shift`

in both possible press and release orders.

As a result:

- the shortcut can finish cleanly first;
- the layout changes only after key release;
- conflicts with many `Alt+Shift+...` and `Ctrl+Shift+...` combinations disappear or become much less noticeable.

## What Systems This Is For

Two different things should be distinguished:

- the general idea of switching on modifier release is useful for many X11 systems;
- this particular implementation is already tied to modern Cinnamon because it uses Cinnamon's D-Bus API to switch layouts safely without desynchronization.

Tested directly on:

- Linux Mint 22.3 Zena
- Cinnamon 6.6.4
- X11

This implementation is intended for systems where all of the following are true:

- Cinnamon 6.6 or newer is used;
- the session is X11, not Wayland;
- the session D-Bus provides `org.Cinnamon` with `Eval`;
- the built-in `Alt+Shift` or `Ctrl+Shift` layout switching conflicts with other shortcuts or behaves unreliably.

So the project is not limited strictly to Linux Mint as a distribution. It should also apply to other systems using the same Cinnamon stack on X11. It is likely useful on:

- LMDE with Cinnamon
- Ubuntu Cinnamon
- Fedora Cinnamon Spin
- Arch Linux / Manjaro with Cinnamon

That is an inference from how Cinnamon works, not a claim of direct testing on all of those systems. On other distributions, you should verify that the same D-Bus API is present and that the session is X11.

For Linux Mint specifically, this means:

- Linux Mint 22.3 and newer with Cinnamon 6.6+ are suitable for this implementation;
- Linux Mint 22.2 and older with older Cinnamon versions will probably need a different backend approach.

If you need a more general X11 solution that is not tied to Cinnamon D-Bus, use the separate repository:

<https://github.com/gugglegum/x11-layout-switch-release>

That project is a better fit when:

- you are on X11 but not on Cinnamon, for example MATE, Xfce, LXDE, Openbox, or another desktop environment;
- you have an older Cinnamon version that does not provide the required `org.Cinnamon` API yet;
- you need a more general XKB-based approach without Cinnamon input sources;
- you want release-based switching on systems where layout state mostly lives in XKB rather than in Cinnamon.

## When This Will Not Help

This solution is not intended for:

- Wayland sessions;
- GNOME Shell, KDE Plasma, Xfce, MATE, and other environments that do not provide `org.Cinnamon`;
- systems where layout switching is not managed through Cinnamon input sources;
- scenarios where the user wants to keep using the stock XKB layout switcher without custom scripts.

## Repository Contents

- `bin/kb-layout-switch-release.sh` — listener that reacts to `Alt+Shift` and `Ctrl+Shift` on key release and talks to Cinnamon through `gdbus`.
- `config/cinnamon-layout-switch-release.conf` — template for the per-user listener config file.
- `autostart/kb-layout-switch-release.desktop.in` — autostart template.
- `install.sh` — installs into `~/.local/bin` by default and creates autostart files in the user's home directory.
- `uninstall.sh` — removes installed files.

## Requirements

- Cinnamon
- X11
- `gdbus`
- `xinput`
- `bash`
- `flock`
- access to the user's session D-Bus

On Linux Mint, all of this is usually already present unless it is a very minimal custom setup.

## Installation

Below is the main installation flow.

### Step 1. Make sure the requirements are present

You need Cinnamon, X11, `gdbus`, `xinput`, `bash`, `flock`, and access to the user session D-Bus.

### Step 2. Run the installer

From the repository root:

```bash
chmod +x install.sh
./install.sh
```

With the default user-local installation, this creates:

- `~/.local/bin/kb-layout-switch-release.sh`
- `~/.config/cinnamon-layout-switch-release.conf`
- `~/.config/autostart/kb-layout-switch-release.desktop`

No root privileges are needed in this mode. If the config file already exists, the installer preserves it.

If you need to target a different user for autostart:

```bash
TARGET_USER=paul ./install.sh
```

If you want an interactive install target selection:

```bash
./install.sh --interactive
```

If you want a system-wide install into `/usr/local/bin`:

```bash
./install.sh --system
```

If you want to install into a custom directory:

```bash
./install.sh --bin-dir /some/path
```

`--system` will usually require `sudo`. `--bin-dir` normally does not require root if the path is inside the user's home directory. If you choose a location outside the home directory, root privileges may be required.

### Step 3. Disable Cinnamon's built-in layout switching

If you want layout switching to be handled only by this listener and not by Cinnamon's built-in shortcuts, it is best to disable the standard bindings:

```bash
gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source "[]"
gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source-backward "[]"
```

It is also best not to keep XKB options such as `grp:alt_shift_toggle` enabled at the same time, otherwise you may get double switching.

### Step 4. Log out and back in, or start the listener manually

After installation, you can simply log out and back in. The autostart entry will launch the listener automatically.

If you do not want to wait, start it manually:

```bash
$HOME/.local/bin/kb-layout-switch-release.sh
```

If you installed with `--system` or `--bin-dir`, use the listener path printed by `install.sh`.

### Step 5. If automatic keyboard detection fails, edit the config

The file `~/.config/cinnamon-layout-switch-release.conf` is created automatically during installation. The listener reads it both during manual startup and when started from autostart.

If layout switching does not work, first find the correct keyboard ID:

```bash
xinput list --short
```

Then open the config file and set, for example:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_ID=8
```

After editing the config, restart the listener or simply log out and back in.

## What `install.sh` Does

- installs the listener
- creates the config file if it does not exist yet
- creates the `.desktop` autostart entry
- preserves an existing config file on repeated installs

## Recommended Checks After Installation

It is useful to confirm that:

- `gsettings get org.cinnamon.desktop.keybindings.wm switch-input-source` returns `[]`
- `gsettings get org.cinnamon.desktop.keybindings.wm switch-input-source-backward` returns `[]`
- `gsettings get org.cinnamon.desktop.input-sources xkb-options` does not contain `grp:alt_shift_toggle`
- the current session is really X11 and not Wayland

## Manual Start

If you do not want to log out, you can start the listener manually:

```bash
$HOME/.local/bin/kb-layout-switch-release.sh
```

If you installed with `--system` or `--bin-dir`, use the listener path printed by `install.sh`.

For debugging:

```bash
KB_LAYOUT_SWITCH_DEBUG=1 $HOME/.local/bin/kb-layout-switch-release.sh
```

For a temporary manual test, you can point it to a specific keyboard explicitly:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_ID=8 $HOME/.local/bin/kb-layout-switch-release.sh
```

During debugging in the VMware test VM, `KEYBOARD_ID=8` pointed to the `AT Translated Set 2 keyboard`. This is a useful example, but not a universal rule: `xinput` IDs depend on the exact system, attached devices, and can sometimes change between boots.

The repository version of the script does not hardcode `ID=8`. It first tries to find the keyboard by name, and `KB_LAYOUT_SWITCH_KEYBOARD_ID` exists only as a manual override for unusual cases or debugging.

## Keyboard Configuration

By default, the listener tries to find the keyboard in this order:

1. `KB_LAYOUT_SWITCH_KEYBOARD_ID`, if explicitly set
2. `AT Translated Set 2 keyboard`
3. fallback to `Virtual core keyboard`

In virtual machines, the keyboard ID is often a small number such as `8`, but that is only an example. On another system the ID can be different.

### How To Find Your Keyboard ID

First, list the available devices:

```bash
xinput list --short
```

You will often see something like:

```text
AT Translated Set 2 keyboard    id=8
```

or some other keyboard name and another ID.

If you already know the device name, you can query only its ID:

```bash
xinput list --id-only "AT Translated Set 2 keyboard"
```

If you want to listen to the X11 master keyboard rather than to one physical keyboard device, you can also inspect:

```bash
xinput list --id-only "Virtual core keyboard"
```

For a permanent setup, put the detected value into:

```text
~/.config/cinnamon-layout-switch-release.conf
```

For example:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_ID=8
```

If the keyboard name is different, you can override the name instead of the ID:

```bash
KB_LAYOUT_SWITCH_KEYBOARD_NAME='AT Translated Set 2 keyboard'
```

The listener reads this file during autostart as well, so there is no need to edit the `.desktop` file by hand.

Environment variables can still be used for temporary manual tests, but for permanent setup it is better to edit the config file itself.

## Why Cinnamon D-Bus Is Used Instead of Direct XKB Switching

On modern Cinnamon versions, switching XKB directly outside Cinnamon can lead to desynchronization:

- XKB already switched;
- Cinnamon still thinks the old layout is active;
- the panel flag and actual text input do not match.

The listener asks Cinnamon to run its own built-in modifier switcher through `org.Cinnamon.Eval`, which is closer to how the native hotkey path works and keeps the state change inside Cinnamon itself.

## Known Notes

- On some Cinnamon versions, the panel flag may disappear for a fraction of a second and then reappear during layout switching. This looks like a flicker in the keyboard applet. Based on observation, this seems to be caused by Cinnamon's own keyboard applet rather than by this listener.
- The script is designed for switching based on two modifiers. If you need more complex logic, you can extend `kb-layout-switch-release.sh`.
- The listener uses `xinput test`, so it must run inside the user's X11 session.

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

To remove a system-wide installation:

```bash
./uninstall.sh --system
```

If you also want to remove the user config:

```bash
./uninstall.sh --purge-config
```

By default, `uninstall.sh` removes the listener and autostart entry, but leaves `~/.config/cinnamon-layout-switch-release.conf` in place so that user settings are not lost unintentionally.

## License

The project is released under the MIT license. This means the code can be used, modified, published, embedded into other projects, and redistributed freely, including for commercial use.
