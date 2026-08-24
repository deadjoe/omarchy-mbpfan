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
  property bool applying: false
  property string applyStatus: ""
  property string applyError: ""

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }
  function loadConfig() {
    if (!cfgProc.running) cfgProc.running = true
  }
  function applyConfig() {
    if (applying) return
    applying = true
    applyStatus = ""
    if (!applyProc.running) applyProc.running = true
  }

  function open() {
    refreshStatus()
    loadConfig()
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // parse /etc/mbpfan.conf for the four keys
  function parseConfig(text) {
    var m
    if ((m = /^low_temp\s*=\s*(\d+)/m.exec(text))) cfgLow = parseInt(m[1])
    if ((m = /^high_temp\s*=\s*(\d+)/m.exec(text))) cfgHigh = parseInt(m[1])
    if ((m = /^max_temp\s*=\s*(\d+)/m.exec(text))) cfgMax = parseInt(m[1])
    if ((m = /^polling_interval\s*=\s*(\d+)/m.exec(text))) cfgPoll = parseInt(m[1])
    configLoaded = true
    syncFields()
  }

  // Always re-sync the fields from the freshly parsed config. Called every
  // time config is read, so reopening the panel (or hitting Reset) shows the
  // real values even if the fields were edited but never applied.
  function syncFields() {
    lowField.text = String(cfgLow)
    highField.text = String(cfgHigh)
    maxField.text = String(cfgMax)
    pollField.text = String(cfgPoll)
  }

  // Discard un-applied edits by re-reading the live config back into the fields.
  function resetToConfig() {
    loadConfig()
  }

  // On losing focus, if a field holds a non-numeric/invalid value, restore
  // that field to the configured default so Apply never sees garbage.
  function validateField(field, defaultVal) {
    var t = field.text.trim()
    if (!/^\d+$/.test(t) || parseInt(t, 10) < 0) field.text = String(defaultVal)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(270))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

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

      // ---- live readout (one line) ----
      Text {
        text: "CPU " + root.temp + "°C  ·  FAN " + root.fan1 + "/" + root.fan2
        anchors.horizontalCenter: parent.horizontalCenter
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      // ---- config editor: 3 columns (2 field cols + buttons stacked right) ----
      Column {
        spacing: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter

        // row 1: low, high, reset (right)
        Row {
          spacing: Style.space(14)
          Row {
            spacing: Style.space(8)
            Text { text: "low"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: lowField; width: Style.space(44); text: ""; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); onEditingFinished: root.validateField(lowField, cfgLow); background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Row {
            spacing: Style.space(8)
            Text { text: "high"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: highField; width: Style.space(44); text: ""; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); onEditingFinished: root.validateField(highField, cfgHigh); background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Button {
            id: resetBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "Reset"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: { if (!root.applying) root.resetToConfig() }
          }
        }

        // row 2: max, poll, apply (right)
        Row {
          spacing: Style.space(14)
          Row {
            spacing: Style.space(8)
            Text { text: "max"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: maxField; width: Style.space(44); text: ""; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); onEditingFinished: root.validateField(maxField, cfgMax); background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Row {
            spacing: Style.space(8)
            Text { text: "poll"; width: Style.space(38); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; color: Qt.darker(root.barForeground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { id: pollField; width: Style.space(44); text: ""; foreground: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.bodySmall; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: Style.space(4); rightPadding: Style.space(4); topPadding: Style.space(1); bottomPadding: Style.space(1); onEditingFinished: root.validateField(pollField, cfgPoll); background: Rectangle { color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06); border.width: Style.spacing.hairline; border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.13); radius: Style.space(2) } }
          }
          Button {
            id: applyBtn
            anchors.verticalCenter: parent.verticalCenter
            text: root.applying ? "Applying…" : "Apply"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            onClicked: { if (!root.applying) root.applyConfig() }
          }
        }
      }

      // ---- apply status ----
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.applyStatus
        visible: root.applyStatus !== ""
        color: root.applyStatus.indexOf("error") === 0 ? "#e05a5a" : "#6fbf73"
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
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
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/deadjoe.mbpfan/bin/mbpfan-status"]
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
      if (exitCode !== 0) console.warn("mbpfan", "config read failed (exit", exitCode + ")")
    }
  }

  // ---- apply (as root via pkexec); capture stderr for a friendly message ----
  Process {
    id: applyProc
    command: ["pkexec", Quickshell.env("HOME") + "/.config/omarchy/plugins/deadjoe.mbpfan/bin/mbpfan-apply",
              lowField.text, highField.text, maxField.text, pollField.text]
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
        root.applyStatus = "error: " + (root.applyError || "apply failed")
      }
      Qt.callLater(function() { root.applyStatus = ""; root.applyError = "" })
    }
  }
}
