import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  // The shell strips __sourceDir from third-party plugin manifests, so resolve
  // the plugin root from this file's own loaded URL instead of the manifest.
  readonly property string sourceDir: decodeURIComponent(Qt.resolvedUrl("../").toString().replace(/^file:\/\//, "").replace(/\/+$/, ""))
  readonly property string controllerPath: sourceDir === "" ? "" : sourceDir + "/bin/localsend-controller"

  property bool ready: false
  property string phase: "starting"
  property string lastError: ""
  property string actionStatus: ""
  property var daemon: ({})
  property var devices: []
  property var incoming: null
  property var transfers: []
  property string payloadKind: ""
  property var selectedPaths: []
  property string payloadLabel: ""

  readonly property bool choosing: chooserProcess.running
  readonly property bool busy: choosing || rpcProcess.running
  readonly property int onlineDeviceCount: {
    var count = 0
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].online === true) count++
    return count
  }
  readonly property bool hasActiveTransfer: {
    for (var i = 0; i < transfers.length; i++) {
      var state = String(transfers[i] && transfers[i].state || "")
      if (state === "preparing" || state === "transferring" || state === "cancelling") return true
    }
    return false
  }

  property bool _intentionalStop: false
  property bool _restartRequested: false
  property int _restartAttempt: 0
  property var _rpcQueue: []
  property var _currentRpc: null
  property string _rpcOutput: ""
  property string _rpcError: ""
  property bool _rpcTimedOut: false
  property bool _snapshotQueued: false
  property int _snapshotFailures: 0
  property string _chooserMode: ""
  property string _chooserOutput: ""
  property string _chooserError: ""
  property var _notifiedRequests: ({})

  function concise(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "..." : value
  }

  function safeRemote(text) {
    return String(text || "Unknown device")
      .replace(/[\u0000-\u001f\u007f]/g, " ")
      .replace(/[<>&]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .substring(0, 120)
  }

  function formatBytes(value) {
    var bytes = Number(value || 0)
    if (!isFinite(bytes) || bytes < 0) bytes = 0
    var units = ["B", "KB", "MB", "GB", "TB"]
    var index = 0
    while (bytes >= 1024 && index < units.length - 1) {
      bytes /= 1024
      index++
    }
    var precision = index === 0 ? 0 : (bytes >= 10 ? 1 : 2)
    return bytes.toFixed(precision) + " " + units[index]
  }

  function baseName(path) {
    var parts = String(path || "").split("/")
    return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
  }

  function startDaemon() {
    if (controllerPath === "" || daemonProcess.running) return
    _intentionalStop = false
    ready = false
    phase = "starting"
    daemonProcess.command = ["setpriv", "--pdeathsig", "TERM", controllerPath, "daemon"]
    daemonProcess.running = true
  }

  function scheduleRestart(immediate) {
    if (_intentionalStop || controllerPath === "") return
    var delay = immediate === true ? 200 : Math.min(30000, 1000 * Math.pow(2, Math.min(_restartAttempt, 5)))
    _restartAttempt++
    restartTimer.interval = delay
    restartTimer.restart()
  }

  function restartDaemon() {
    _restartRequested = true
    _intentionalStop = false
    ready = false
    phase = "restarting"
    _rpcQueue = []
    _snapshotQueued = false
    if (rpcProcess.running) rpcProcess.running = false
    if (daemonProcess.running) daemonProcess.running = false
    else scheduleRestart(true)
  }

  function handleDaemonLine(line) {
    var parsed = null
    try {
      parsed = JSON.parse(String(line || ""))
    } catch (error) {
      lastError = concise(line)
      return
    }
    if (parsed && parsed.event === "ready" && parsed.ok === true) {
      ready = true
      phase = "running"
      lastError = ""
      _restartAttempt = 0
      startupTimeout.stop()
      queueSnapshot()
      return
    }
    if (parsed && parsed.ok === false && parsed.error) {
      lastError = concise(parsed.error.message || "LocalSend controller failed")
    }
  }

  function queueRpc(kind, args, successMessage, clearPayload) {
    if (!ready) {
      if (kind !== "snapshot") {
        lastError = "LocalSend receiver is not ready"
        actionStatusTimer.restart()
      }
      return
    }
    if (kind === "snapshot") {
      if (_snapshotQueued || (_currentRpc && _currentRpc.kind === "snapshot")) return
      _snapshotQueued = true
    }
    var queue = _rpcQueue.slice()
    queue.push({
      kind: kind,
      args: args,
      successMessage: successMessage || "",
      clearPayload: clearPayload === true
    })
    _rpcQueue = queue
    runNextRpc()
  }

  function queueSnapshot() {
    queueRpc("snapshot", ["snapshot"], "", false)
  }

  function runNextRpc() {
    if (rpcProcess.running || _currentRpc || _rpcQueue.length === 0 || controllerPath === "") return
    var queue = _rpcQueue.slice()
    _currentRpc = queue.shift()
    _rpcQueue = queue
    _rpcOutput = ""
    _rpcError = ""
    _rpcTimedOut = false
    rpcProcess.command = [controllerPath].concat(_currentRpc.args)
    rpcProcess.running = true
    rpcTimeout.restart()
  }

  function finishRpc(exitCode) {
    rpcTimeout.stop()
    var current = _currentRpc
    _currentRpc = null
    if (!current) {
      runNextRpc()
      return
    }
    if (current.kind === "snapshot") _snapshotQueued = false

    var raw = String(_rpcOutput || rpcStdout.text || "").trim()
    var response = null
    try {
      response = raw === "" ? null : JSON.parse(raw)
    } catch (error) {
      response = null
    }

    if (_rpcTimedOut || !response || response.ok !== true) {
      var message = _rpcTimedOut
        ? "Controller request timed out"
        : (response && response.error ? String(response.error.message || "Controller request failed") : concise(_rpcError || raw || "Controller request failed"))
      if (current.kind === "snapshot") {
        _snapshotFailures++
        if (_snapshotFailures >= 3 && daemonProcess.running) restartDaemon()
      } else {
        lastError = concise(message)
        actionStatus = ""
        actionStatusTimer.restart()
      }
    } else if (current.kind === "snapshot") {
      _snapshotFailures = 0
      applySnapshot(response.result)
    } else {
      if (current.clearPayload) clearPayload()
      lastError = ""
      actionStatus = current.successMessage
      if (actionStatus !== "") actionStatusTimer.restart()
      queueSnapshot()
    }
    runNextRpc()
  }

  function applySnapshot(snapshot) {
    if (!snapshot || !snapshot.daemon || !(snapshot.devices instanceof Array) || !(snapshot.transfers instanceof Array)) {
      lastError = "Controller returned an invalid snapshot"
      return
    }
    var previousRequest = incoming && incoming.id ? String(incoming.id) : ""
    daemon = snapshot.daemon
    devices = snapshot.devices
    incoming = snapshot.incoming || null
    transfers = snapshot.transfers
    ready = String(snapshot.daemon.status || "") === "running"
    phase = ready ? "running" : String(snapshot.daemon.status || "unavailable")
    if (snapshot.error && snapshot.error.message) lastError = concise(snapshot.error.message)
    if (incoming && incoming.id && String(incoming.id) !== previousRequest) notifyIncoming(incoming)
  }

  function notifyIncoming(request) {
    var id = String(request.id || "")
    if (id === "" || _notifiedRequests[id]) return
    var next = ({})
    for (var key in _notifiedRequests) next[key] = _notifiedRequests[key]
    next[id] = true
    _notifiedRequests = next
    var sender = safeRemote(request.sender && request.sender.alias)
    var count = request.files instanceof Array ? request.files.length : 0
    var body = request.messagePreview !== null && request.messagePreview !== undefined
      ? "Clipboard text from " + sender
      : formatBytes(request.totalBytes) + " in " + count + (count === 1 ? " file" : " files") + " from " + sender
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "LocalSend",
      "--urgency", "normal",
      "--glyph", "󰒊",
      "--exec", "omarchy-shell -q shell summon bredda.localsend",
      "Incoming LocalSend request",
      body
    ])
  }

  function refresh() {
    queueRpc("refresh", ["refresh"], "Searching for nearby devices", false)
  }

  function chooseFiles() {
    startChooser("files")
  }

  function chooseFolder() {
    startChooser("folder")
  }

  function startChooser(mode) {
    if (chooserProcess.running) return
    _chooserMode = mode
    _chooserOutput = ""
    _chooserError = ""
    chooserProcess.command = mode === "folder"
      ? ["omarchy-file-select", "--title", "Share a folder with LocalSend", "--directory"]
      : ["omarchy-file-select", "--title", "Share files with LocalSend", "--multiple"]
    chooserProcess.running = true
  }

  function chooseClipboard() {
    payloadKind = "clipboard"
    selectedPaths = []
    payloadLabel = "Clipboard text"
    actionStatus = "Choose a nearby device"
    actionStatusTimer.restart()
  }

  function finishChooser(exitCode) {
    if (exitCode === 1) return
    if (exitCode !== 0) {
      lastError = concise(_chooserError || "File chooser failed")
      actionStatusTimer.restart()
      return
    }
    var lines = String(_chooserOutput || chooserStdout.text || "").replace(/\r/g, "").split("\n")
    var paths = []
    for (var i = 0; i < lines.length; i++) if (lines[i].length > 0) paths.push(lines[i])
    if (paths.length === 0) return
    payloadKind = "files"
    selectedPaths = paths
    payloadLabel = _chooserMode === "folder"
      ? "Folder: " + baseName(paths[0])
      : (paths.length === 1 ? baseName(paths[0]) : paths.length + " files selected")
    actionStatus = "Choose a nearby device"
    actionStatusTimer.restart()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "bredda.localsend"])
  }

  function clearPayload() {
    payloadKind = ""
    selectedPaths = []
    payloadLabel = ""
  }

  function sendToDevice(fingerprint) {
    var device = String(fingerprint || "")
    if (device === "" || payloadKind === "") return
    if (payloadKind === "clipboard") {
      queueRpc("send", ["send-clipboard", "--device", device], "Sending clipboard", true)
      return
    }
    var args = ["send-files", "--device", device]
    for (var i = 0; i < selectedPaths.length; i++) args.push("--path", String(selectedPaths[i]))
    queueRpc("send", args, "Transfer requested", true)
  }

  function acceptRequest(id) {
    queueRpc("accept", ["accept", "--request", String(id || "")], "Transfer accepted", false)
  }

  function declineRequest(id) {
    queueRpc("decline", ["decline", "--request", String(id || "")], "Transfer declined", false)
  }

  function cancelTransfer(id) {
    queueRpc("cancel", ["cancel", "--transfer", String(id || "")], "Cancelling transfer", false)
  }

  onControllerPathChanged: if (controllerPath !== "") launchTimer.restart()

  Component.onDestruction: {
    _intentionalStop = true
    restartTimer.stop()
    if (rpcProcess.running) rpcProcess.running = false
    if (chooserProcess.running) chooserProcess.running = false
    if (daemonProcess.running) daemonProcess.running = false
  }

  Timer {
    id: launchTimer
    interval: 100
    repeat: false
    onTriggered: root.startDaemon()
  }

  Timer {
    id: restartTimer
    interval: 1000
    repeat: false
    onTriggered: root.startDaemon()
  }

  Timer {
    id: startupTimeout
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root.ready && daemonProcess.running) {
        root.lastError = "LocalSend receiver did not become ready"
        daemonProcess.running = false
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.incoming || root.hasActiveTransfer ? 450 : 1500
    repeat: true
    running: root.ready
    triggeredOnStart: true
    onTriggered: root.queueSnapshot()
  }

  Timer {
    id: rpcTimeout
    interval: 38000
    repeat: false
    onTriggered: {
      if (rpcProcess.running) {
        root._rpcTimedOut = true
        rpcProcess.running = false
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: daemonProcess
    command: []
    running: false
    stdout: SplitParser { onRead: line => root.handleDaemonLine(line) }
    stderr: SplitParser {
      onRead: function(line) {
        var value = root.concise(line)
        if (value !== "" && !root.ready) root.lastError = value
      }
    }
    onStarted: {
      root.phase = "starting"
      startupTimeout.restart()
    }
    onExited: function(exitCode, exitStatus) {
      startupTimeout.stop()
      root.ready = false
      root.phase = "stopped"
      root.daemon = ({})
      root.devices = []
      root.incoming = null
      root.transfers = []
      root._rpcQueue = []
      root._snapshotQueued = false
      if (root._intentionalStop) return
      var immediate = root._restartRequested
      root._restartRequested = false
      root.scheduleRestart(immediate)
    }
  }

  Process {
    id: rpcProcess
    command: []
    running: false
    stdout: StdioCollector {
      id: rpcStdout
      waitForEnd: true
      onStreamFinished: root._rpcOutput = text
    }
    stderr: StdioCollector {
      id: rpcStderr
      waitForEnd: true
      onStreamFinished: root._rpcError = text
    }
    onExited: function(exitCode) { root.finishRpc(exitCode) }
  }

  Process {
    id: chooserProcess
    command: []
    running: false
    stdout: StdioCollector {
      id: chooserStdout
      waitForEnd: true
      onStreamFinished: root._chooserOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._chooserError = text
    }
    onExited: function(exitCode) { root.finishChooser(exitCode) }
  }
}
