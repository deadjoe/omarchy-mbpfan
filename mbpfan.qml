import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// mbpfan — Omarchy top-bar widget.
// Shows CPU temperature and fan speed (read from the mbpfan/applesmc stack),
// with a popup to view and edit mbpfan defaults.
//
// Low-CPU: a single shell call reads all values every `interval` seconds
// (default 4s). Spawning `mbpfan-status` a few times per minute is negligible;
// no busy-polling, no per-tick allocations.

BarWidget {
  id: root
  moduleName: "mbpfan"

  // ---- live data ----
  property int temp: 0
  property int fan1: 0
  property int fan2: 0
  readonly property string tempText: temp + "°"
  readonly property string tooltipText: "CPU " + temp + "°C  ·  FAN " + fan1 + " / " + fan2

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  // ---- panel routing (BarPanel contract) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ---- low-CPU polling ----
  Timer {
    interval: Number(root.setting("interval", 4000))
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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

  // ---- panel ----
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- bar button ----
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.tempText
    hasVisualContent: root.tempText !== ""
    tooltipText: root.tooltipText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }
  }
}
