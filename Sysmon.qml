import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "demi.sysmon"

  readonly property string scriptPath: String(Qt.resolvedUrl("collect.sh")).replace(/^file:\/\//, "")

  property var cpu: ({})
  property var gpu: ({})
  property bool popupOpen: false

  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color dim: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.62)
  readonly property color faint: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

  function cpuString(key) { var value = root.cpu ? root.cpu[key] : undefined; return value === undefined || value === null ? "" : String(value); }
  function gpuString(key) { var value = root.gpu ? root.gpu[key] : undefined; return value === undefined || value === null ? "" : String(value); }
  function cpuNumber(key) { var value = parseFloat(root.cpuString(key)); return isFinite(value) ? value : -1; }
  function gpuNumber(key) { var value = parseFloat(root.gpuString(key)); return isFinite(value) ? value : -1; }

  readonly property int cpuTemp: cpuNumber("cpu_temp")
  readonly property int gpuTemp: gpuNumber("temp")
  readonly property real cpuUsage: cpuNumber("cpu_usage")
  readonly property real gpuUsage: gpuNumber("util")
  readonly property real memUsed: cpuNumber("mem_used")
  readonly property real memTotal: cpuNumber("mem_total")
  readonly property real swapUsed: cpuNumber("swap_used")
  readonly property real swapTotal: cpuNumber("swap_total")

  readonly property var fanItems: root.parseFans(root.cpuString("fans"))

  function parseFans(raw) {
    var list = []
    if (!raw) return list
    var parts = String(raw).split(";")
    for (var i = 0; i < parts.length; i++) {
      var entry = parts[i]
      if (entry === "") continue
      var split = entry.indexOf("=")
      if (split <= 0) continue
      var rpm = parseFloat(entry.substring(split + 1))
      if (!isFinite(rpm)) continue
      list.push({ name: entry.substring(0, split), rpm: rpm })
    }
    return list
  }

  function fmtTemp(value) { return value >= 0 ? Math.round(value) + "°" : "--"; }
  function fmtPercent(value) { return value >= 0 ? Math.round(value) + "%" : "--"; }
  function fmtClockMHz(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " MHz" : "--"; }
  function fmtGHz(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? (n / 1000).toFixed(1) + " GHz" : "--"; }
  function fmtGB(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? (n / 1024).toFixed(1) + " GB" : "--"; }
  function fmtMiB(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " MiB" : "--"; }
  function fmtWatts(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " W" : "--"; }
  function fmtRpm(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " rpm" : "--"; }
  function fmtUptime(value) { var n = parseFloat(value); if (!isFinite(n) || n <= 0) return "--"; var days = Math.floor(n / 86400); var hours = Math.floor((n % 86400) / 3600); var minutes = Math.floor((n % 3600) / 60); if (days > 0) return days + "d " + hours + "h"; if (hours > 0) return hours + "h " + minutes + "m"; return minutes + "m"; }

  function tempColor(temperature) {
    if (!(temperature >= 0)) return root.dim
    if (temperature >= 85) return root.bar ? root.bar.urgent : Commons.Color.urgent
    if (temperature >= 75) return Commons.Color.accent
    return root.fg
  }

  function tooltipText() {
    var parts = ["CPU " + root.fmtTemp(root.cpuTemp)]
    if (root.cpuUsage >= 0) parts.push(root.fmtPercent(root.cpuUsage))
    if (root.cpuNumber("cpu_freq") > 0) parts.push(root.fmtGHz(root.cpuNumber("cpu_freq")))
    var text = parts.join(" · ")
    var gn = root.gpuString("name")
    var gd = root.gpuString("driver")
    if (gn !== "" || root.gpuTemp >= 0) {
      var gparts = [gn !== "" ? gn : "NVIDIA GPU"]
      if (root.gpuTemp >= 0) gparts.push(root.fmtTemp(root.gpuTemp))
      if (root.gpuUsage >= 0) gparts.push(root.fmtPercent(root.gpuUsage))
      if (root.gpuNumber("clock") > 0) gparts.push(root.fmtClockMHz(root.gpuNumber("clock")))
      if (gd !== "") gparts.push("drv " + gd)
      text += " — " + gparts.join(" · ")
    }
    return text
  }

  function updateCpu(raw) {
    var next = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var split = line.indexOf("=")
      if (split <= 0) continue
      next[line.substring(0, split)] = line.substring(split + 1)
    }
    root.cpu = next
  }

  function updateGpu(line) {
    var parts = String(line || "").split(",")
    if (parts.length < 3) return
    function clean(value) {
      var text = String(value === undefined ? "" : value).trim()
      if (text === "N/A" || text === "[N/A]" || text === "[Not Supported]" || text === "[Unknown Error]") return ""
      return text
    }
    var gname = clean(parts[0])
    if (gname === "") gname = "NVIDIA GPU"
    root.gpu = ({
      name: gname,
      driver: clean(parts[1]),
      temp: clean(parts[2]),
      fan: clean(parts[3]),
      util: clean(parts[4]),
      memutil: clean(parts[5]),
      clock: clean(parts[6]),
      memclock: clean(parts[7]),
      power: clean(parts[8]),
      vram_used: clean(parts[9]),
      vram_total: clean(parts[10]),
      pstate: parts[11] !== undefined ? clean(parts[11]) : ""
    })
  }

  Process {
    id: cpuProc
    command: ["bash", root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateCpu(text) }
  }

  Timer {
    interval: root.popupOpen ? 1000 : 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!cpuProc.running) cpuProc.running = true
  }

  property bool nvidiaAvailable: false

  Process {
    id: detectProc
    command: ["bash", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.nvidiaAvailable = String(text).trim() !== ""
    }
  }

  Process {
    id: gpuProc
    running: root.nvidiaAvailable
    onRunningChanged: if (!running) gpuRestart.restart()
    command: ["nvidia-smi", "--query-gpu=name,driver_version,temperature.gpu,fan.speed,utilization.gpu,utilization.memory,clocks.current.graphics,clocks.current.memory,power.draw,memory.used,memory.total,pstate", "--format=csv,noheader,nounits", "-lms", "1000"]
    stdout: SplitParser { onRead: function(line) { root.updateGpu(line) } }
  }

  Timer {
    id: gpuRestart
    interval: 3000
    onTriggered: if (root.nvidiaAvailable && !gpuProc.running) gpuProc.running = true
  }

  readonly property bool hasGpu: gpuString("name") !== "" || gpuTemp >= 0

  visible: true
  implicitWidth: root.vertical ? barSize : barRow.implicitWidth + Style.space(12)
  implicitHeight: barSize

  Row {
    id: barRow
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(9)

    Row {
      spacing: Style.space(3)
      Text { textFormat: Text.PlainText; text: "󰻠"; anchors.verticalCenter: parent.verticalCenter; color: root.tempColor(root.cpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
      Text { textFormat: Text.PlainText; text: root.fmtTemp(root.cpuTemp); anchors.verticalCenter: parent.verticalCenter; color: root.tempColor(root.cpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
    }

    Row {
      spacing: Style.space(3)
      visible: root.hasGpu
      Text { textFormat: Text.PlainText; text: "󰢮"; anchors.verticalCenter: parent.verticalCenter; color: root.tempColor(root.gpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
      Text { textFormat: Text.PlainText; text: root.fmtTemp(root.gpuTemp); anchors.verticalCenter: parent.verticalCenter; color: root.tempColor(root.gpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body }
    }
  }

  Column {
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 0
    Text { textFormat: Text.PlainText; text: root.fmtTemp(root.cpuTemp); anchors.horizontalCenter: parent.horizontalCenter; color: root.tempColor(root.cpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
    Text { textFormat: Text.PlainText; visible: root.hasGpu; text: root.fmtTemp(root.gpuTemp); anchors.horizontalCenter: parent.horizontalCenter; color: root.tempColor(root.gpuTemp); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
  }

  property bool tooltipHovered: hoverArea.containsMouse

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText())
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) { if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop") }
      else { root.popupOpen = !root.popupOpen }
    }
  }

  component StatRow: Item {
    id: row
    property string label: ""
    property string value: ""
    property color valueColor: root.fg
    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)
    Text { id: labelText; textFormat: Text.PlainText; text: row.label; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.body }
    Text { id: valueText; textFormat: Text.PlainText; text: row.value; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, parent.width - labelText.implicitWidth - Style.space(12)); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; color: row.valueColor; font.family: Style.font.family; font.pixelSize: Style.font.body }
  }

  component Meter: Item {
    id: meter
    property real value: 0
    width: parent ? parent.width : 0
    implicitHeight: Style.space(5)
    Rectangle { anchors.fill: parent; radius: height / 2; color: root.faint }
    Rectangle { width: parent.width * Math.max(0, Math.min(1, meter.value)); height: parent.height; radius: height / 2; color: root.fg; Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
  }

  function close() { root.popupOpen = false }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      clip: true
      spacing: Style.space(9)

      Row {
        width: parent.width
        spacing: Style.space(10)
        Text { textFormat: Text.PlainText; text: "󰓅"; anchors.verticalCenter: parent.verticalCenter; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.heading }
        Column {
          width: parent.width - Style.space(34)
          spacing: Style.space(1)
          Text { textFormat: Text.PlainText; text: "System monitor"; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
          Text { textFormat: Text.PlainText; text: "up " + root.fmtUptime(root.cpuNumber("uptime")); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
      }

      PanelSeparator { foreground: root.fg }
      PanelSectionHeader { text: "PROCESSOR"; foreground: root.fg }
      Text { textFormat: Text.PlainText; width: parent.width; text: (root.cpuString("cpu_model") || "CPU") + (root.cpuNumber("cpu_cores") > 0 ? "  ·  " + root.cpuNumber("cpu_cores") + " threads" : ""); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
      StatRow { label: "Temperature"; value: root.fmtTemp(root.cpuTemp); valueColor: root.tempColor(root.cpuTemp) }
      StatRow { label: "Usage"; value: root.fmtPercent(root.cpuUsage) }
      Meter { value: root.cpuUsage / 100 }
      StatRow { label: "Frequency"; value: root.fmtGHz(root.cpuNumber("cpu_freq")) + " / " + root.fmtGHz(root.cpuNumber("cpu_max_freq")) }
      StatRow { label: "Load average"; value: root.cpuString("load") || "--" }

      Column {
        visible: root.hasGpu
        width: parent.width
        spacing: Style.space(9)

        PanelSeparator { foreground: root.fg }
        PanelSectionHeader { text: "GRAPHICS"; foreground: root.fg }
        Text { textFormat: Text.PlainText; width: parent.width; text: root.gpuString("name") + (root.gpuString("driver") !== "" ? " • Driver " + root.gpuString("driver") : ""); color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
        StatRow { label: "Temperature"; value: root.fmtTemp(root.gpuTemp); valueColor: root.tempColor(root.gpuTemp) }
        StatRow { label: "Usage"; value: root.fmtPercent(root.gpuUsage) + (root.gpuNumber("memutil") >= 0 ? "  ·  mem " + root.fmtPercent(root.gpuNumber("memutil")) : "") }
        Meter { value: root.gpuUsage / 100 }
        StatRow { label: "VRAM"; value: root.gpuNumber("vram_total") > 0 ? root.fmtMiB(root.gpuNumber("vram_used")) + " / " + root.fmtMiB(root.gpuNumber("vram_total")) : "--" }
        StatRow { label: "Core clock"; value: root.fmtClockMHz(root.gpuNumber("clock")) }
        StatRow { label: "Memory clock"; value: root.fmtClockMHz(root.gpuNumber("memclock")) }
        StatRow { visible: root.gpuNumber("power") > 0; label: "Power draw"; value: root.fmtWatts(root.gpuNumber("power")) }
        StatRow { visible: root.gpuString("pstate") !== ""; label: "P-state"; value: root.gpuString("pstate") }
      }

      PanelSeparator { foreground: root.fg }
      PanelSectionHeader { text: "MEMORY"; foreground: root.fg }
      StatRow { label: "RAM"; value: root.memTotal > 0 ? root.fmtGB(root.memUsed) + " / " + root.fmtGB(root.memTotal) + "  (" + Math.round(root.memUsed / root.memTotal * 100) + "%)" : "--" }
      Meter { value: root.memTotal > 0 ? root.memUsed / root.memTotal : 0 }
      StatRow { visible: root.swapTotal > 0; label: "Swap"; value: root.fmtGB(root.swapUsed) + " / " + root.fmtGB(root.swapTotal) }

      PanelSeparator { foreground: root.fg }
      PanelSectionHeader { text: "STORAGE & COOLING"; foreground: root.fg }
      StatRow { label: "NVMe"; value: root.fmtTemp(root.cpuNumber("nvme_temp")); valueColor: root.tempColor(root.cpuNumber("nvme_temp")) }
      StatRow { visible: root.hasGpu; label: "GPU fan"; value: { var f = root.gpuNumber("fan"); if (f < 0) return "--"; if (f === 0) return "0% (semi-passive)"; return f + "%"; } }
      Repeater {
        model: root.fanItems
        delegate: StatRow {
          label: modelData.name
          value: root.fmtRpm(modelData.rpm)
        }
      }
      Text { textFormat: Text.PlainText; visible: root.fanItems.length === 0; width: parent.width; wrapMode: Text.WordWrap; text: "No motherboard fan sensors found. Load nct6687/nct6775 if available."; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45); font.family: Style.font.family; font.pixelSize: Style.font.caption }
    }
  }
}
