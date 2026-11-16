import QtQuick
import Quickshell
import Quickshell.Io

// The live side of the widget: which herdr agents are running and what they
// are doing, plus the gateway services. herdr owns agent state (its
// integrations report working / blocked / idle); this file polls it, remembers
// when each pane last changed state, and runs the helper scripts in bin/.
Item {
  id: root
  visible: false

  // The panel is open: poll gateways too, and agents a little faster.
  property bool detailed: false

  readonly property string binDir: String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, "")

  property bool herdrAvailable: false
  property var agents: []
  readonly property int workingCount: countStatus("working")
  readonly property int blockedCount: countStatus("blocked")

  property var gateways: []

  // paneId -> { status, sinceMs }; survives polls so durations keep counting.
  property var stateSince: ({})

  function countStatus(status) {
    var n = 0
    for (var i = 0; i < agents.length; i++) if (agents[i].status === status) n++
    return n
  }

  // ---------------------------------------------------------------- agents

  Timer {
    interval: root.detailed ? 2000 : 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!agentProcess.running) agentProcess.running = true
  }

  Process {
    id: agentProcess
    running: false
    command: ["herdr", "agent", "list"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgents(text)
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.applyAgents("") }
  }

  function projectName(cwd) {
    var path = String(cwd || "").replace(/\/+$/, "")
    var home = Quickshell.env("HOME") || ""
    if (path === "" ) return "unknown"
    if (path === home) return "~"
    return path.slice(path.lastIndexOf("/") + 1)
  }

  function applyAgents(output) {
    var parsed = null
    try { parsed = JSON.parse(String(output || "")) } catch (e) { parsed = null }
    var list = parsed && parsed.result && parsed.result.agents ? parsed.result.agents : null
    herdrAvailable = list !== null
    if (!list) {
      if (agents.length > 0) agents = []
      return
    }

    var now = Date.now()
    var since = ({})
    var rows = []
    for (var i = 0; i < list.length; i++) {
      var a = list[i] || {}
      var paneId = String(a.pane_id || "")
      var status = String(a.agent_status || "unknown")
      var prev = stateSince[paneId]
      since[paneId] = prev && prev.status === status ? prev : { status: status, sinceMs: now }
      var cwd = String(a.foreground_cwd || a.cwd || "")
      rows.push({
        paneId: paneId,
        workspaceId: String(a.workspace_id || ""),
        agent: String(a.agent || ""),
        project: projectName(cwd),
        cwd: cwd,
        status: status,
        sinceMs: since[paneId].sinceMs,
        focused: a.focused === true
      })
    }

    // Needs-you first, then working, then the rest; stable by project name.
    var rank = { blocked: 0, working: 1, idle: 2 }
    rows.sort(function(x, y) {
      var rx = rank[x.status] !== undefined ? rank[x.status] : 3
      var ry = rank[y.status] !== undefined ? rank[y.status] : 3
      return rx !== ry ? rx - ry : x.project.localeCompare(y.project)
    })

    stateSince = since
    if (JSON.stringify(rows) !== JSON.stringify(agents)) agents = rows
  }

  // -------------------------------------------------------------- gateways

  Timer {
    interval: 10000
    running: root.detailed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshGateways()
  }

  Process {
    id: gatewayProcess
    running: false
    command: [root.binDir + "/agent-gateways", "status"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
        if (parsed && parsed.length !== undefined) root.gateways = parsed
      }
    }
  }

  function refreshGateways() {
    if (!gatewayProcess.running) gatewayProcess.running = true
  }

  Process {
    id: gatewayAction
    running: false
    onExited: root.refreshGateways()
  }

  function gatewayCommand(action, unit) {
    if (gatewayAction.running) return
    gatewayAction.command = [root.binDir + "/agent-gateways", action, unit]
    gatewayAction.running = true
  }

  // ---------------------------------------------------------------- actions

  // Detached so the agent window outlives a shell reload.
  function focusAgent(paneId) {
    Quickshell.execDetached([root.binDir + "/agent-focus", paneId])
  }

  function launchAgent() {
    Quickshell.execDetached([root.binDir + "/agent-launch"])
  }

  function openHerdr() {
    Quickshell.execDetached([root.binDir + "/agent-raise"])
  }
}
