import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "demi.sysmon"

  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("collect.sh")).replace(/^file:\/\//, ""))
  // Per-instance id so several bars/screens don't share one CPU-usage baseline.
  readonly property string instanceId: String(Math.floor(Math.random() * 1e9))

  property var cpu: ({})
  property var gpu: ({})
  property bool popupOpen: false
  property string popupSection: "general"   // "cpu" | "gpu" | "general"

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

  property string fansRaw: ""
  property int fanSensorCount: 0
  readonly property bool allFansStopped: fanSensorCount > 0 && fanModel.count === 0

  ListModel { id: fanModel }

  // Sync the model in place so the Repeater keeps its delegates between ticks.
  function syncFans(raw) {
    if (raw === root.fansRaw) return
    root.fansRaw = raw
    var all = root.parseFans(raw)
    root.fanSensorCount = all.length
    var list = []
    for (var i = 0; i < all.length; i++) if (all[i].rpm > 0) list.push(all[i])
    var same = fanModel.count === list.length
    for (var j = 0; same && j < list.length; j++) if (fanModel.get(j).name !== list[j].name) same = false
    if (same) {
      for (var k = 0; k < list.length; k++) fanModel.setProperty(k, "rpm", list[k].rpm)
    } else {
      fanModel.clear()
      for (var m = 0; m < list.length; m++) fanModel.append(list[m])
    }
  }

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
  function fmtGB(value) { var n = parseFloat(value); return isFinite(n) && n >= 0 ? (n / 1024).toFixed(1) + " GiB" : "--"; }
  function fmtMiB(value) { var n = parseFloat(value); return isFinite(n) && n >= 0 ? Math.round(n) + " MiB" : "--"; }
  function fmtWatts(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " W" : "--"; }
  function fmtRpm(value) { var n = parseFloat(value); return isFinite(n) && n > 0 ? Math.round(n) + " rpm" : "--"; }
  function fmtUptime(value) { var n = parseFloat(value); if (!isFinite(n) || n <= 0) return "--"; var days = Math.floor(n / 86400); var hours = Math.floor((n % 86400) / 3600); var minutes = Math.floor((n % 3600) / 60); if (days > 0) return days + "d " + hours + "h"; if (hours > 0) return hours + "h " + minutes + "m"; return minutes + "m"; }

  function tempColor(temperature) {
    if (!(temperature >= 0)) return root.dim
    if (temperature >= 85) return root.bar ? root.bar.urgent : Commons.Color.urgent
    if (temperature >= 75) return Commons.Color.accent
    return root.fg
  }

  function cpuTip() {
    var parts = ["CPU " + root.fmtTemp(root.cpuTemp)]
    if (root.cpuUsage >= 0) parts.push(root.fmtPercent(root.cpuUsage))
    if (root.cpuNumber("cpu_freq") > 0) parts.push(root.fmtGHz(root.cpuNumber("cpu_freq")))
    return parts.join(" · ")
  }

  function gpuTip() {
    var gn = root.gpuString("name")
    var gd = root.gpuString("driver")
    var gparts = [gn !== "" ? gn : "NVIDIA GPU"]
    if (root.gpuTemp >= 0) gparts.push(root.fmtTemp(root.gpuTemp))
    if (root.gpuUsage >= 0) gparts.push(root.fmtPercent(root.gpuUsage))
    if (root.gpuNumber("clock") > 0) gparts.push(root.fmtClockMHz(root.gpuNumber("clock")))
    if (gd !== "") gparts.push("drv " + gd)
    return gparts.join(" · ")
  }

  function sysTip() {
    var parts = ["CPU " + root.fmtTemp(root.cpuTemp)]
    if (root.hasGpu) parts.push("GPU " + root.fmtTemp(root.gpuTemp))
    if (root.memTotal > 0) parts.push("RAM " + Math.round(root.memUsed / root.memTotal * 100) + "%")
    var nv = root.cpuNumber("nvme_temp")
    if (nv >= 0) parts.push("NVMe " + root.fmtTemp(nv))
    return parts.join(" · ")
  }

  function toggleSection(name) {
    if (root.popupOpen && root.popupSection === name) root.popupOpen = false
    else { root.popupSection = name; root.popupOpen = true }
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
    root.syncFans(next["fans"] || "")
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
    command: ["bash", root.scriptPath, root.instanceId]
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

  // Driver may not be ready at login: keep probing until a GPU shows up.
  Timer {
    interval: 15000
    running: !root.nvidiaAvailable
    repeat: true
    onTriggered: if (!detectProc.running) detectProc.running = true
  }

  Process {
    id: gpuProc
    running: root.nvidiaAvailable
    onRunningChanged: if (!running) { root.gpu = ({}); gpuRestart.restart() }
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
  implicitWidth: root.vertical ? barSize : barRow.implicitWidth + Style.space(8)
  implicitHeight: root.vertical ? barCol.implicitHeight + Style.space(8) : barSize

  readonly property string barFont: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property real ramPercent: root.memTotal > 0 && root.memUsed >= 0 ? root.memUsed / root.memTotal * 100 : -1
  readonly property color ramColor: root.ramPercent >= 90 ? (root.bar ? root.bar.urgent : Commons.Color.urgent) : (root.ramPercent >= 80 ? Commons.Color.accent : root.fg)
  readonly property int maxTemp: Math.max(root.cpuTemp, root.hasGpu ? root.gpuTemp : -1)

  // One clickable area of the bar. `section` decides what the popup shows.
  component Zone: Item {
    id: zone
    property string section: "general"
    property string tip: ""
    readonly property bool hovered: zoneMouse.containsMouse
    readonly property bool active: root.popupOpen && root.popupSection === zone.section
    default property alias content: inner.data
    implicitWidth: inner.childrenRect.width + Style.space(10)
    implicitHeight: root.vertical ? inner.childrenRect.height + Style.space(6) : root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: root.vertical ? 0 : Style.space(3)
      anchors.bottomMargin: root.vertical ? 0 : Style.space(3)
      radius: Style.space(5)
      color: root.fg
      opacity: zone.active ? 0.16 : (zone.hovered ? 0.08 : 0)
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Item {
      id: inner
      anchors.centerIn: parent
      width: childrenRect.width
      height: childrenRect.height
    }

    MouseArea {
      id: zoneMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: if (root.bar && !root.popupOpen) root.bar.showTooltip(zone, zone.tip)
      onExited: if (root.bar) root.bar.hideTooltip(zone)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) { if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop") }
        else { if (root.bar) root.bar.hideTooltip(zone); root.toggleSection(zone.section) }
      }
    }
  }

  property bool tooltipHovered: cpuZone.hovered || gpuZone.hovered || sysZone.hovered

  Row {
    id: barRow
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    Zone {
      id: cpuZone
      section: "cpu"
      tip: root.cpuTip()
      Row {
        spacing: Style.space(3)
        Text { textFormat: Text.PlainText; text: "󰻠"; color: root.tempColor(root.cpuTemp); font.family: root.barFont; font.pixelSize: Style.font.body }
        Text { textFormat: Text.PlainText; text: root.fmtTemp(root.cpuTemp); color: root.tempColor(root.cpuTemp); font.family: root.barFont; font.pixelSize: Style.font.body }
      }
    }

    Zone {
      id: gpuZone
      section: "gpu"
      visible: root.hasGpu
      tip: root.gpuTip()
      Row {
        spacing: Style.space(3)
        Text { textFormat: Text.PlainText; text: "󰢮"; color: root.tempColor(root.gpuTemp); font.family: root.barFont; font.pixelSize: Style.font.body }
        Text { textFormat: Text.PlainText; text: root.fmtTemp(root.gpuTemp); color: root.tempColor(root.gpuTemp); font.family: root.barFont; font.pixelSize: Style.font.body }
      }
    }

    Zone {
      id: sysZone
      section: "general"
      tip: root.sysTip()
      Text { textFormat: Text.PlainText; text: root.fmtPercent(root.ramPercent); color: root.ramColor; font.family: root.barFont; font.pixelSize: Style.font.body }
    }
  }

  Column {
    id: barCol
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 0
    // Vertical bar: the same three zones, stacked. They re-use the zones above
    // through their own copies so each keeps its own hover and click handling.
    Zone {
      section: "cpu"
      tip: root.cpuTip()
      Text { textFormat: Text.PlainText; text: root.fmtTemp(root.cpuTemp); color: root.tempColor(root.cpuTemp); font.family: root.barFont; font.pixelSize: Style.font.caption }
    }
    Zone {
      section: "gpu"
      visible: root.hasGpu
      tip: root.gpuTip()
      Text { textFormat: Text.PlainText; text: root.fmtTemp(root.gpuTemp); color: root.tempColor(root.gpuTemp); font.family: root.barFont; font.pixelSize: Style.font.caption }
    }
    Zone {
      section: "general"
      tip: root.sysTip()
      Text { textFormat: Text.PlainText; text: root.fmtPercent(root.ramPercent); color: root.ramColor; font.family: root.barFont; font.pixelSize: Style.font.caption }
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
    Text { id: valueText; textFormat: Text.PlainText; text: row.value; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Math.max(0, Math.min(implicitWidth, parent.width - labelText.implicitWidth - Style.space(12))); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; color: row.valueColor; font.family: Style.font.family; font.pixelSize: Style.font.body }
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

  readonly property Item activeAnchor: root.vertical ? root : (popupSection === "cpu" ? cpuZone : (popupSection === "gpu" && root.hasGpu ? gpuZone : sysZone))
  readonly property string popupTitle: popupSection === "cpu" ? "Processor" : (popupSection === "gpu" ? "Graphics" : "System monitor")
  readonly property string popupIcon: popupSection === "cpu" ? "󰻠" : (popupSection === "gpu" ? "󰢮" : "󰓅")
  readonly property string popupSubtitle: {
    if (popupSection === "cpu") return (root.cpuString("cpu_model").replace(/\s+\d+-Core Processor$/, "") || "CPU") + (root.cpuNumber("cpu_cores") > 0 ? "  ·  " + root.cpuNumber("cpu_cores") + " threads" : "")
    if (popupSection === "gpu") return root.gpuString("name") + (root.gpuString("driver") !== "" ? "  ·  Driver " + root.gpuString("driver") : "")
    return "up " + root.fmtUptime(root.cpuNumber("uptime"))
  }

  PopupCard {
    id: popup
    anchorItem: root.activeAnchor
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
        Text { id: headIcon; textFormat: Text.PlainText; text: root.popupIcon; anchors.verticalCenter: parent.verticalCenter; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.heading }
        Column {
          width: Math.max(0, parent.width - headIcon.implicitWidth - parent.spacing)
          spacing: Style.space(1)
          Text { textFormat: Text.PlainText; width: parent.width; text: root.popupTitle; color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true; elide: Text.ElideRight }
          Text { textFormat: Text.PlainText; width: parent.width; text: root.popupSubtitle; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
        }
      }

      PanelSeparator { foreground: root.fg }

      // ---------------- CPU ----------------
      Column {
        visible: root.popupSection === "cpu"
        width: parent.width
        spacing: Style.space(9)

        StatRow { label: "Temperature"; value: root.fmtTemp(root.cpuTemp); valueColor: root.tempColor(root.cpuTemp) }
        StatRow { label: "Usage"; value: root.fmtPercent(root.cpuUsage) }
        Meter { value: root.cpuUsage / 100 }
        StatRow { label: "Frequency"; value: root.fmtGHz(root.cpuNumber("cpu_freq")) + " / " + root.fmtGHz(root.cpuNumber("cpu_max_freq")) }
        StatRow { label: "Load average"; value: root.cpuString("load") || "--" }
        StatRow { visible: root.cpuNumber("fan_cpu") > 0; label: "CPU fan"; value: root.fmtRpm(root.cpuNumber("fan_cpu")) }
      }

      // ---------------- GPU ----------------
      Column {
        visible: root.popupSection === "gpu"
        width: parent.width
        spacing: Style.space(9)

        StatRow { label: "Temperature"; value: root.fmtTemp(root.gpuTemp); valueColor: root.tempColor(root.gpuTemp) }
        StatRow { label: "Usage"; value: root.fmtPercent(root.gpuUsage) + (root.gpuNumber("memutil") >= 0 ? "  ·  mem " + root.fmtPercent(root.gpuNumber("memutil")) : "") }
        Meter { value: root.gpuUsage / 100 }
        StatRow { label: "VRAM"; value: root.gpuNumber("vram_total") > 0 ? root.fmtMiB(root.gpuNumber("vram_used")) + " / " + root.fmtMiB(root.gpuNumber("vram_total")) : "--" }
        Meter { visible: root.gpuNumber("vram_total") > 0; value: root.gpuNumber("vram_total") > 0 ? root.gpuNumber("vram_used") / root.gpuNumber("vram_total") : 0 }
        StatRow { label: "Core clock"; value: root.fmtClockMHz(root.gpuNumber("clock")) }
        StatRow { label: "Memory clock"; value: root.fmtClockMHz(root.gpuNumber("memclock")) }
        StatRow { visible: root.gpuNumber("power") > 0; label: "Power draw"; value: root.fmtWatts(root.gpuNumber("power")) }
        StatRow { visible: root.gpuString("pstate") !== ""; label: "P-state"; value: root.gpuString("pstate") }
        StatRow { label: "Fan"; value: { var f = root.gpuNumber("fan"); if (f < 0) return "--"; if (f === 0) return "0% (semi-passive)"; return f + "%"; } }
      }

      // ---------------- General ----------------
      Column {
        visible: root.popupSection === "general"
        width: parent.width
        spacing: Style.space(9)

        PanelSectionHeader { text: "OVERVIEW"; foreground: root.fg }
        StatRow { label: "CPU"; value: root.fmtTemp(root.cpuTemp) + "  ·  " + root.fmtPercent(root.cpuUsage); valueColor: root.tempColor(root.cpuTemp) }
        StatRow { visible: root.hasGpu; label: "GPU"; value: root.fmtTemp(root.gpuTemp) + "  ·  " + root.fmtPercent(root.gpuUsage); valueColor: root.tempColor(root.gpuTemp) }
        StatRow { label: "Load average"; value: root.cpuString("load") || "--" }

        PanelSeparator { foreground: root.fg }
        PanelSectionHeader { text: "MEMORY"; foreground: root.fg }
        StatRow { label: "RAM"; value: root.memTotal > 0 ? root.fmtGB(root.memUsed) + " / " + root.fmtGB(root.memTotal) + "  (" + Math.round(root.memUsed / root.memTotal * 100) + "%)" : "--" }
        Meter { value: root.memTotal > 0 ? root.memUsed / root.memTotal : 0 }
        StatRow { visible: root.swapTotal > 0; label: "Swap"; value: root.fmtGB(root.swapUsed) + " / " + root.fmtGB(root.swapTotal) }

        PanelSeparator { foreground: root.fg }
        PanelSectionHeader { text: "STORAGE & COOLING"; foreground: root.fg }
        StatRow { label: "NVMe"; value: root.fmtTemp(root.cpuNumber("nvme_temp")); valueColor: root.tempColor(root.cpuNumber("nvme_temp")) }
        Repeater {
          model: fanModel
          delegate: StatRow {
            label: model.name
            value: root.fmtRpm(model.rpm)
          }
        }
        Text { textFormat: Text.PlainText; visible: root.allFansStopped; width: parent.width; text: "All motherboard fans are stopped."; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45); font.family: Style.font.family; font.pixelSize: Style.font.caption }
        Text { textFormat: Text.PlainText; visible: root.fanSensorCount === 0; width: parent.width; wrapMode: Text.WordWrap; text: "No motherboard fan sensors found. Load nct6687/nct6775 if available."; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45); font.family: Style.font.family; font.pixelSize: Style.font.caption }
      }
    }
  }
}
