# MBPFan — Omarchy top-bar widget for mbpfan

A [Quickshell](https://quickshell.io) bar-widget for [Omarchy](https://omarchy.org) that watches
[`mbpfan`](https://github.com/linux-on-mac/mbpfan) on Apple hardware: it shows **CPU temperature**
and **fan speed** right in the top bar, and opens a small panel where you can view and edit
mbpfan's temperature thresholds (`low_temp`, `high_temp`, `max_temp`).

Designed to be cheap: it reads the sensors with one tiny shell call every few seconds and only
polls while the panel is open — the monitoring widget itself does not burn CPU.

## Features

- Live CPU temperature (°C) and both fan speeds (RPM) on the bar, updated every few seconds.
- Hover tooltip with the full temperature + fan readout.
- Click to open a compact settings panel:
  - Current temperature + fan RPM.
  - Editable mbpfan temperature thresholds: `low_temp`, `high_temp`, `max_temp`.
  - Keeps `polling_interval` at the upstream one-second default so mbpfan remains responsive.
  - **Apply** validates the values, then edits `/etc/mbpfan.conf` and restarts `mbpfan` through
    `pkexec` on **fixed trusted system binaries only** (`sed`, `systemctl`) — nothing is installed
    system-wide, and no plugin code or file is ever executed/read as root.
  - **Discard** restores the last successfully loaded values without writing anything.
  - The info icon explains all four settings. The defaults icon stages mbpfan's upstream defaults
    (`63 / 66 / 86 · 1s`) after confirmation; **Apply** is still required to save them.
  - Apply stays disabled until the config is loaded, the draft has changed, and every value is valid.
  - Opening the panel does not focus an editor; typing changes nothing until you select a field.
- Follows the Omarchy bar-widget contract; opens anchored next to its own bar slot (right side).

## Requirements

This release is tested on a **15-inch Retina MacBook Pro (Late 2013)**. It targets Intel Apple
hardware that runs `mbpfan` through the `applesmc` and `coretemp` drivers, but its monitoring path
currently expects the two-fan ApplesMC layout described below. Other Mac models may expose a
different fan count or thermal-zone number and can require a small read-script adjustment.

This widget is only useful if `mbpfan` is installed, configured, and actually reading your
machine's sensors. Before installing, confirm that the exact paths in the verification steps below
exist on your machine.

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
not universal. The widget's **Apply** accepts only `20 ≤ low_temp ≤ 63`,
`low_temp < high_temp ≤ 66`, and `high_temp < max_temp ≤ 90`. It also writes
`polling_interval = 1`, the current upstream default. These conservative limits prevent accepted
settings from leaving the fans at minimum until an excessive temperature or delaying sensor
response. Values outside those ranges are rejected without touching the config.

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

### If the widget shows 0°C / 0 RPM after install

Run the read script manually; if it prints real numbers but the bar shows `0`, re-read the
`applesmc` path (some machines expose a different fan numbering):

```sh
~/.config/omarchy/plugins/io.github.deadjoe.mbpfan/bin/mbpfan-status
```

Then check the prerequisites above (mbpfan service active, config present, sensors readable).

## Updating

```sh
omarchy plugin update io.github.deadjoe.mbpfan
```

An update reloads the plugin in the running shell automatically, so no manual `omarchy restart
shell` is needed; restart the shell only if the widget misbehaves after an update.

## Usage

- **Left-click** the thermometer in the bar → opens the settings panel.
- **Right-click** → force a refresh.
- In the panel, edit the temperature thresholds and press **Apply**. Administrator authorization
  may be requested for the config update and service restart; only fixed trusted binaries are
  elevated. **Discard** restores the last loaded values. Closing the panel also saves nothing;
  changes are not written until you select **Apply**. Hover the info icon for a compact explanation
  of all settings, or use the defaults icon to stage mbpfan's upstream defaults after confirmation.

## How the values are read

`bin/mbpfan-status` reads the `applesmc` sysfs files directly:

- Temperature: `/sys/class/thermal/thermal_zone1/temp` (CPU package).
- Fan speeds: `/sys/devices/platform/applesmc.768/fan1_input` and `fan2_input`.

It prints a single line `TEMP FAN1 FAN2` every refresh. Nothing is written by the read path.

## How the settings are applied

Applying needs no helper and installs nothing: both privileged steps use only fixed trusted
system binaries, and the only user-controlled input is the three digits-only temperature values.

1. The panel first requires all four settings to be present in the loaded config. It then validates
   the temperature values strictly (digits only, `20 ≤ low ≤ 63`, `low < high ≤ 66`,
   `high < max ≤ 90`), canonicalizes them to short decimal strings, and fixes polling at the
   upstream one-second default.
2. The panel invokes `pkexec /usr/bin/sed -i … /etc/mbpfan.conf`, where each expression is built from a
   fixed key name (`low_temp`, `high_temp`, `max_temp`, `polling_interval`) and either a validated
   digit value or the fixed value `1` — no user-controlled path, file, or code is in the expressions.
3. The panel invokes `pkexec /usr/bin/systemctl restart mbpfan` to reload the service.

No plugin code is ever executed as root, no user-writable file or path is ever opened by root, and
there is nothing to install — so there is no script-elevation, file/symlink TOCTOU, or install-source
race surface at all. Polkit may request authorization for the config write and service restart.

## Uninstall / disable

```sh
omarchy plugin disable io.github.deadjoe.mbpfan
omarchy plugin remove io.github.deadjoe.mbpfan
```

Removing also resets the bar layout that referenced the widget.

## Notes

- The widget runs **unsandboxed** inside the long-lived `omarchy-shell` process (like all Omarchy
  plugins). It only reads system sensor files and only elevates fixed trusted system binaries
  (`/usr/bin/sed`, `/usr/bin/systemctl`) when you press Apply; nothing from the plugin is installed
  system-wide.
- First-party `omarchy.*` id namespace is reserved; this plugin uses `io.github.deadjoe.mbpfan`. Change the
  `id` (and the script paths in `mbpfan.qml`/`Panel.qml`) if you fork it under your own
  namespace.

## License

MIT. See [LICENSE](LICENSE).
