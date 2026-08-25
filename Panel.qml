import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// mbpfan settings panel — live fan/temp readout plus editable mbpfan defaults.
// Opened from the mbpfan bar widget. Low-CPU: only polls while open, and only
// re-reads the config when opened / after an apply.

Panel {
  id: root
  moduleName: "mbpfan"
  ipcTarget: "mbpfan"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- live + config state ----
  property int temp: 0
  property int fan1: 0
  property int fan2: 0
  property int cfgLow: 0
  property int cfgHigh: 0
  property int cfgMax: 0
  property int cfgPoll: 0
  property bool configLoaded: false
  property string configError: ""
  property bool applying: false
  property bool defaultsConfirming: false
  property string applyStatus: ""
  property string applyError: ""
  readonly property bool fieldsValid: validateAll()
  readonly property bool dirty: configLoaded && (
    lowField.text.trim() !== String(cfgLow)
    || highField.text.trim() !== String(cfgHigh)
    || maxField.text.trim() !== String(cfgMax))
  readonly property bool pollNeedsNormalization: configLoaded && cfgPoll !== 1
  readonly property bool pendingChanges: dirty || pollNeedsNormalization

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }
  function loadConfig() {
    if (cfgProc.running) return
    configLoaded = false
    configError = ""
    cfgProc.running = true
  }
  // Strict validation before any elevation. The upper bounds follow mbpfan's
  // documented defaults: fans stay at minimum below low_temp, begin ramping
  // above high_temp, and poll every second. Lower temperatures are safe because
  // they only make fan response more aggressive.
  function validateAll() {
    var low = lowField.text.trim(), high = highField.text.trim(), max = maxField.text.trim()
    if (!/^\d+$/.test(low) || !/^\d+$/.test(high) || !/^\d+$/.test(max)) return false
    var l = parseInt(low, 10), h = parseInt(high, 10)
    var m = parseInt(max, 10)
    if (!(l < h && h < m)) return false
    if (l < 20 || l > 63 || h > 66 || m > 90) return false
    return true
  }

  // Build a sed expression that rewrites one threshold key in /etc/mbpfan.conf.
  // KEY is a fixed key name; VAL has already been validated as digits-only, so
  // the expression cannot carry shell/sed metacharacters from user input.
  function sedExpr(key, val) {
    return "s/^\\([[:space:]]*" + key + "[[:space:]]*=[[:space:]]*\\)" + ".*" + "/\\1" + val + "/"
  }

  function applyConfig() {
    if (applying) return
    if (!configLoaded) {
      applyStatus = "error: " + (configError || "configuration is not loaded")
      statusClearTimer.restart()
      return
    }
    if (!pendingChanges) return
    if (!validateAll()) {
      applyStatus = "error: use 20 ≤ low ≤ 63, low < high ≤ 66, high < max ≤ 90"
      statusClearTimer.restart()
      return
    }
    applying = true
    defaultsConfirming = false
    applyStatus = ""
    applyError = ""
    // Canonicalize validated input before it crosses the privilege boundary.
    // This removes leading zeroes and bounds every user-controlled argument to
    // the short decimal representation of its accepted numeric value.
    var low = String(parseInt(lowField.text.trim(), 10))
    var high = String(parseInt(highField.text.trim(), 10))
    var max = String(parseInt(maxField.text.trim(), 10))
    applyProc.command = ["/usr/bin/pkexec", "/usr/bin/sed", "-i",
                         "-e", sedExpr("low_temp", low),
                         "-e", sedExpr("high_temp", high),
                         "-e", sedExpr("max_temp", max),
                         "-e", sedExpr("polling_interval", "1"),
                         "/etc/mbpfan.conf"]
    if (!applyProc.running) applyProc.running = true
  }

  function open() {
    defaultsConfirming = false
    refreshStatus()
    loadConfig()
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // parse /etc/mbpfan.conf for the four keys
  function parseConfig(text) {
    var low = /^\s*low_temp\s*=\s*(\d+)\s*(?:#.*)?$/m.exec(text)
    var high = /^\s*high_temp\s*=\s*(\d+)\s*(?:#.*)?$/m.exec(text)
    var max = /^\s*max_temp\s*=\s*(\d+)\s*(?:#.*)?$/m.exec(text)
    var poll = /^\s*polling_interval\s*=\s*(\d+)\s*(?:#.*)?$/m.exec(text)
    if (!low || !high || !max || !poll) {
      configLoaded = false
      configError = "/etc/mbpfan.conf is missing a required setting"
      return
    }
    cfgLow = parseInt(low[1], 10)
    cfgHigh = parseInt(high[1], 10)
    cfgMax = parseInt(max[1], 10)
    cfgPoll = parseInt(poll[1], 10)
    configError = ""
    configLoaded = true
    syncFields()
  }

  // Always re-sync the draft fields from the last successfully parsed config.
  function syncFields() {
    lowField.text = String(cfgLow)
    highField.text = String(cfgHigh)
    maxField.text = String(cfgMax)
  }

  // Discard un-applied edits synchronously from the last successful read.
  function discardChanges() {
    if (configLoaded && !applying) {
      defaultsConfirming = false
      syncFields()
    }
  }

  function stageDefaults() {
    if (!configLoaded || applying) return
    lowField.text = "63"
    highField.text = "66"
    maxField.text = "86"
    defaultsConfirming = false
    applyStatus = "defaults staged — Apply to save"
    statusClearTimer.restart()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      width: parent.width
      implicitHeight: column.implicitHeight
      blocked: lowField.activeFocus || highField.activeFocus || maxField.activeFocus
      onCloseRequested: {
        if (root.defaultsConfirming) root.defaultsConfirming = false
        else root.close()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

      // ---- header: fan icon + title + subtitle ----
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

        Text {
          id: heroIcon
          text: "\uf2c9"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "MBPFan"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: "FAN AND TEMPERATURE"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }

      PanelSeparator {
        foreground: root.barForeground
        anchors.horizontalCenter: parent.horizontalCenter
      }

      // ---- live readout plus compact settings actions ----
      Item {
        width: parent.width
        implicitHeight: Math.max(liveReadout.implicitHeight, settingsActions.implicitHeight)

        Text {
          id: liveReadout
          text: "CPU " + root.temp + "°C  ·  FAN " + root.fan1 + "/" + root.fan2
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          id: settingsActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Button {
            iconText: "ⓘ"
            tooltipText: "low — minimum fan speed below this temperature (°C)\nhigh — start increasing fan speed above this temperature (°C)\nmax — maximum fan speed above this temperature (°C)\npoll — temperature check interval (fixed at 1 second)"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            iconSize: Style.font.bodySmall
            horizontalPadding: Style.space(3)
            verticalPadding: Style.space(1)
          }

          Button {
            iconText: "↺"
            tooltipText: "Restore upstream defaults"
            enabled: root.configLoaded && !root.applying
            opacity: enabled ? 1 : 0.45
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            iconSize: Style.font.bodySmall
            horizontalPadding: Style.space(3)
            verticalPadding: Style.space(1)
            onClicked: root.defaultsConfirming = true
          }
        }
      }

      // ---- config editor: draft fields plus explicit discard/apply actions ----
      Column {
        spacing: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter

        // row 1: low, high, discard (right)
        Row {
          spacing: Style.space(14)
          Row {
            spacing: Style.space(8)
            Text { text: "low"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: lowField; width: Style.space(44); text: ""; enabled: root.configLoaded && !root.applying; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }; background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Row {
            spacing: Style.space(8)
            Text { text: "high"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: highField; width: Style.space(44); text: ""; enabled: root.configLoaded && !root.applying; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }; background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Button {
            id: discardBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "Discard"
            enabled: root.dirty && !root.applying
            opacity: enabled ? 1 : 0.45
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: root.discardChanges()
          }
        }

        // row 2: max, fixed safe polling interval, apply (right)
        Row {
          spacing: Style.space(14)
          Row {
            spacing: Style.space(8)
            Text { text: "max"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: maxField; width: Style.space(44); text: ""; enabled: root.configLoaded && !root.applying; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }; background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Row {
            spacing: Style.space(8)
            Text { text: "poll"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { width: Style.space(44); text: root.configLoaded && root.cfgPoll !== 1 ? root.cfgPoll + "→1s" : "1s"; anchors.verticalCenter: parent.verticalCenter; color: root.configLoaded && root.cfgPoll !== 1 ? "#e0a85a" : root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
          Button {
            id: applyBtn
            anchors.verticalCenter: parent.verticalCenter
            text: root.applying ? "Applying…" : "Apply"
            enabled: root.configLoaded && root.pendingChanges && root.fieldsValid && !root.applying
            opacity: enabled ? 1 : 0.45
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: root.applyConfig()
          }
        }
      }

      // ---- compact confirmation: stage upstream defaults, never write here ----
      Column {
        visible: root.defaultsConfirming
        width: parent.width
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: "Use mbpfan defaults? 63 / 66 / 86 · 1s"
          horizontalAlignment: Text.AlignHCenter
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Button {
            text: "Cancel"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: root.defaultsConfirming = false
          }

          Button {
            text: "Use defaults"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: root.stageDefaults()
          }
        }
      }

      // ---- apply status ----
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.applyStatus || root.configError
          || (root.dirty && !root.fieldsValid
            ? "use 20 ≤ low ≤ 63, low < high ≤ 66, high < max ≤ 90"
            : "")
        visible: text !== ""
        color: text.indexOf("error") === 0 || text.indexOf("failed") !== -1 || root.configError !== "" || (root.dirty && !root.fieldsValid) ? "#e05a5a" : "#6fbf73"
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      }
    }
  }

  // ---- live status poll (only while open) ----
  Timer {
    id: statusTimer
    interval: Number(root.setting("interval", 4000))
    running: root.opened
    repeat: true
    onTriggered: root.refreshStatus()
  }
  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.deadjoe.mbpfan/bin/mbpfan-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length >= 3) {
          root.temp = parseInt(parts[0]) || 0
          root.fan1 = parseInt(parts[1]) || 0
          root.fan2 = parseInt(parts[2]) || 0
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) console.warn("mbpfan", "status read failed (exit", exitCode + ")")
    }
  }

  // ---- config read (on open / after apply) ----
  Process {
    id: cfgProc
    command: ["cat", "/etc/mbpfan.conf"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() { root.parseConfig(String(text)) }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.configLoaded = false
        root.configError = "could not read /etc/mbpfan.conf"
        console.warn("mbpfan", "config read failed (exit", exitCode + ")")
      }
    }
  }

  // Keep the status/error text readable for a moment instead of clearing it
  // within the same event-loop tick (otherwise "applied ✓" is never visible).
  Timer {
    id: statusClearTimer
    interval: 2500
    onTriggered: { root.applyStatus = ""; root.applyError = "" }
  }

  // ---- apply: two privileged steps, both on fixed trusted system binaries ----
  // Step 1 (applyProc): /usr/bin/sed rewrites the four threshold keys in the
  // root-owned /etc/mbpfan.conf. Its expressions are built purely from fixed
  // key names and the digits-only values validated above, so no path, file,
  // content, or code originates from the user-writable plugin checkout — and
  // nothing has to be installed as root anywhere.
  // Step 2 (restartProc): /usr/bin/systemctl restarts the mbpfan service.
  Process {
    id: applyProc
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() { root.applyError = String(text).trim() }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.applying = false
        root.applyStatus = "error: " + (root.applyError || "write config failed")
        statusClearTimer.restart()
        return
      }
      applyError = ""
      restartProc.command = ["/usr/bin/pkexec", "/usr/bin/systemctl", "restart", "mbpfan"]
      if (!restartProc.running) restartProc.running = true
    }
  }

  Process {
    id: restartProc
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() { root.applyError = String(text).trim() }
    }
    onExited: function(exitCode, exitStatus) {
      root.applying = false
      if (exitCode === 0) {
        root.applyStatus = "applied ✓"
        root.loadConfig()
        root.refreshStatus()
      } else {
        // sed already committed the config in step 1, so report this partial
        // success accurately and re-read the file instead of implying rollback.
        root.applyStatus = "config saved; restart failed: " + (root.applyError || "authorization or service error")
        root.loadConfig()
      }
      statusClearTimer.restart()
    }
  }
}
