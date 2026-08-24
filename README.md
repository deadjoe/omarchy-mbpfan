# MBPFan — Omarchy top-bar widget for mbpfan

A [Quickshell](https://quickshell.io) bar-widget for [Omarchy](https://omarchy.org) that watches
[`mbpfan`](https://github.com/linux-on-mac/mbpfan) on Apple hardware: it shows **CPU temperature**
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
  - **Apply** validates the values, then runs a **root-owned helper** (`/usr/local/libexec/mbpfan-apply`)
    via `pkexec`; the helper writes `/etc/mbpfan.conf` and restarts `mbpfan`. The privileged side never
    executes or reads anything from the plugin checkout.
  - **Reset** re-reads the live config back into the fields.
  - Fields validate on focus loss — non-numeric input reverts to the configured value.
- Follows the Omarchy bar-widget contract; opens anchored next to its own bar slot (right side).

## Requirements

This widget targets **Apple hardware that `mbpfan` supports and that exposes the `applesmc`
**sensor driver** — that is, any Apple machine with fans and the ApplesMC controller, such as
MacBook, MacBook Pro, MacBook Air, iMac, or Mac mini running Linux. If your machine can run
`mbpfan`, it can use this widget.

This widget is only useful if `mbpfan` is installed, configured, and actually reading your
machine's sensors. The bar widget reads the same `applesmc` files `mbpfan` uses, so if `mbpfan`
doesn't see a temperature or fan speed, neither will this widget.

### 1. Install mbpfan

```sh
omarchy pkg add mbpfan
```

### 2. Configure mbpfan

Create or edit `/etc/mbpfan.conf`. A minimal working config looks like:

```ini
[general]
min_fan1_speed = 2160
max_fan1_speed = 6200
low_temp = 63
high_temp = 66
max_temp = 86
polling_interval = 1
```

- `low_temp`  — below this the fans idle at minimum speed.
- `high_temp` — above this the fans ramp up.
- `max_temp`  — above this the fans run at maximum speed.
- `polling_interval` — how often (in seconds) mbpfan polls the sensors.
- The optional `min_fan*_speed` / `max_fan*_speed` keys override the values read from the
  `applesmc` driver. You may omit them to let mbpfan auto-detect from the driver.

Adjust the thresholds to your own machine's thermal profile; the values above are typical but
not universal.

### 3. Enable and start the service

```sh
sudo systemctl enable --now mbpfan
sudo systemctl status mbpfan    # confirm it shows active (running)
```

### 4. Confirm the sensors are readable (do this before installing the widget)

Verify the hardware, driver, and config are all in place so the widget has data to show:

```sh
# The applesmc driver is loaded and exposes fan + temp sensors
ls /sys/devices/platform/applesmc.768/fan1_input   # should exist

# A live CPU temperature (divide by 1000 for degrees Celsius)
cat /sys/class/thermal/thermal_zone1/temp          # e.g. 78000 → 78°C

# Live fan speeds in RPM
cat /sys/devices/platform/applesmc.768/fan1_input
cat /sys/devices/platform/applesmc.768/fan2_input

# mbpfan is running and actively managing the fans
systemctl is-active mbpfan                          # should print "active"

# mbpfan can parse your config (look for a successful start in the log)
sudo systemctl status mbpfan --no-pager | tail -5
```

If any of the above returns nothing or an error, fix that first — the widget will show the same
result as these commands.

### 5. A Nerd Font for the bar

The widget's bar icon is a Nerd Font glyph (the thermometer). Omarchy's default monospace font is
already a Nerd Font, so this is usually already satisfied. If the icon appears as a hollow box
(tofu) rather than a thermometer, your bar font is not a Nerd Font and the glyph is missing.

## Install

Use the official Omarchy plugin command (from a git URL of this repo):

```sh
omarchy plugin add <this-repo-url> --enable
```

The plugin lands in `~/.config/omarchy/plugins/io.github.deadjoe.mbpfan/` and the widget is placed in the
**right** section of the top bar (per `barWidget.defaultSection`). If it doesn't appear, open
`~/.config/omarchy/shell.json` and ensure the `right` layout contains `{ "id": "io.github.deadjoe.mbpfan" }`,
then reload the shell.

### Install the privileged helper (one-time)

**Apply** runs a small helper as root through `pkexec`. For that to work, install the helper once to a
**root-owned, non-user-writable** path. The panel always invokes this fixed path, so `pkexec` never
executes or reads anything from the user-writable plugin checkout:

```sh
sudo install -m 0755 ~/.config/omarchy/plugins/io.github.deadjoe.mbpfan/bin/mbpfan-apply /usr/local/libexec/mbpfan-apply
ls -l /usr/local/libexec/mbpfan-apply   # must show root root, mode 0755
```

If the helper is missing, the panel's **Apply** button shows an error with this install command.

### If the widget shows 0°C / 0 RPM after install

Run the read script manually; if it prints real numbers but the bar shows `0`, re-read the
`applesmc` path (some machines expose a different fan numbering):

```sh
~/.config/omarchy/plugins/io.github.deadjoe.mbpfan/bin/mbpfan-status
```

Then check the prerequisites above (mbpfan service active, config present, sensors readable).

## Usage

- **Left-click** the thermometer in the bar → opens the settings panel.
- **Right-click** → force a refresh.
- In the panel, edit the values and press **Apply** (a graphical `pkexec` prompt appears; the
  **root-owned helper** `/usr/local/libexec/mbpfan-apply` writes `/etc/mbpfan.conf` and restarts
  `mbpfan`). **Reset** discards un-applied edits.

## How the values are read

`bin/mbpfan-status` reads the `applesmc` sysfs files directly:

- Temperature: `/sys/class/thermal/thermal_zone1/temp` (CPU package).
- Fan speeds: `/sys/devices/platform/applesmc.768/fan1_input` and `fan2_input`.

It prints a single line `TEMP FAN1 FAN2` every refresh. Nothing is written by the read path.

## How the settings are applied

Applying uses a **root-owned helper at a fixed, non-user-writable path**:

1. The panel validates the four values (digits only, `low < high < max`, `poll >= 1`).
2. The panel launches `pkexec /usr/local/libexec/mbpfan-apply LOW HIGH MAX POLL` — a helper installed
   once to a root-owned location (see [Install](#install)); the user session cannot modify it.
3. The helper re-validates the four integer arguments, edits the root-owned `/etc/mbpfan.conf`, and
   restarts the `mbpfan` service.

The privileged side therefore only ever executes the root-owned helper and only ever reads/writes the
root-owned `/etc/mbpfan.conf`; no user-writable code, file, or pathname is on the root path, and the
panel never passes a user-controlled path to `pkexec`. This removes the replace-the-file / symlink
TOCTOU surface entirely. (One `pkexec` prompt covers both the config write and the service restart.)

## Uninstall / disable

```sh
omarchy plugin disable io.github.deadjoe.mbpfan
omarchy plugin remove io.github.deadjoe.mbpfan
```

Removing also resets the bar layout that referenced the widget.

## Notes

- The widget runs **unsandboxed** inside the long-lived `omarchy-shell` process (like all Omarchy
  plugins). It only reads system sensor files, and only elevates the root-owned helper
  `/usr/local/libexec/mbpfan-apply` when you press Apply. If you install it yourself, verify its
  ownership: `ls -l /usr/local/libexec/mbpfan-apply` must show `root root` with mode `0755`.
- First-party `omarchy.*` id namespace is reserved; this plugin uses `io.github.deadjoe.mbpfan`. Change the
  `id` (and the script paths in `mbpfan.qml`/`Panel.qml`) if you fork it under your own
  namespace.

## License

MIT. See [LICENSE](LICENSE).
