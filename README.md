# MBPFan — Omarchy top-bar widget for mbpfan

A [Quickshell](https://quickshell.io) bar-widget for [Omarchy](https://omarchy.org) that watches
[`mbpfan`](https://github.com/linux-on-mac/mbpfan) on Intel MacBooks: it shows **CPU temperature**
and **fan speed** right in the top bar, and opens a small panel where you can view and edit
mbpfan's fan-control defaults (`low_temp`, `high_temp`, `max_temp`, `polling_interval`).

Designed to be cheap: it reads the sensors with one tiny shell call every few seconds and only
polls while the panel is open — the monitoring widget itself does not burn CPU.

## Features

- Live CPU temperature (°C) and both fan speeds (RPM) on the bar, updated every few seconds.
- Hover tooltip with the full temperature + fan readout.
- Click to open a compact settings panel:
  - Current temperature + fan RPM.
  - Editable mbpfan defaults: `low_temp`, `high_temp`, `max_temp`, `polling_interval`.
  - **Apply** writes `/etc/mbpfan.conf` (via `pkexec`) and restarts `mbpfan`.
  - **Reset** re-reads the live config back into the fields.
  - Fields validate on focus loss — non-numeric input reverts to the configured value.
- Follows the Omarchy bar-widget contract; opens anchored next to its own bar slot (right side).

## Requirements

- **Omarchy** (Intel Mac build).
- **macOS Intel / ApplesMC** hardware (`applesmc` driver present, e.g. a MacBook Pro / Air).
- **mbpfan** installed and running as a service:
  ```sh
  omarchy pkg add mbpfan
  ```
  `/etc/mbpfan.conf` must exist (created by `mbpfan`). The widget reads and edits it.
  `mbpfan.service` should be **enabled** so it starts at boot:
  ```sh
  sudo systemctl enable --now mbpfan
  ```
- A Nerd Font for the bar (Omarchy's default monospace) for the thermometer glyph.

## Install

Use the official Omarchy plugin command (from a git URL of this repo):

```sh
omarchy plugin add <this-repo-url> --enable
```

Or install from a local checkout:

```sh
omarchy plugin add /home/joe/omarchy-mbpfan --enable
```

The plugin lands in `~/.config/omarchy/plugins/joe.mbpfan/` and the widget is placed in the
**right** section of the top bar (per `barWidget.defaultSection`). If it doesn't appear, open
`~/.config/omarchy/shell.json` and ensure the `right` layout contains `{ "id": "joe.mbpfan" }`,
then reload the shell.

## Usage

- **Left-click** the thermometer in the bar → opens the settings panel.
- **Right-click** → force a refresh.
- In the panel, edit the values and press **Apply** (a graphical `pkexec` password prompt appears;
  `/etc/mbpfan.conf` is written and `mbpfan` is restarted). **Reset** discards un-applied edits.

## How the values are read

`bin/mbpfan-status` reads the `applesmc` sysfs files directly:

- Temperature: `/sys/class/thermal/thermal_zone1/temp` (CPU package).
- Fan speeds: `/sys/devices/platform/applesmc.768/fan1_input` and `fan2_input`.

It prints a single line `TEMP FAN1 FAN2` every refresh. Nothing is written by the read path.

## How the settings are applied

`bin/mbpfan-apply LOW HIGH MAX POLL` edits `/etc/mbpfan.conf` (as root, via `pkexec`),
validating that all values are integers and `low < high < max`, then restarts `mbpfan`.
Invalid input is rejected without touching the config.

## Uninstall / disable

```sh
omarchy plugin disable joe.mbpfan
omarchy plugin remove joe.mbpfan
```

Removing also resets the bar layout that referenced the widget.

## Notes

- The widget runs **unsandboxed** inside the long-lived `omarchy-shell` process (like all Omarchy
  plugins). It only reads system sensor files and edits `/etc/mbpfan.conf` when you press Apply.
- First-party `omarchy.*` id namespace is reserved; this plugin uses `joe.mbpfan`. Change the
  `id` (and the script paths in `mbpfan.qml`/`Panel.qml`) if you fork it under your own
  namespace.

## License

MIT. See [LICENSE](LICENSE).
