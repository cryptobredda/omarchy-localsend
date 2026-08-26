import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "bredda.localsend"
  ipcTarget: "bredda.localsend"
  manageIpc: false

  readonly property var localsend: bar?.shell?.serviceFor("bredda.localsend")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barIconColor: localsend && localsend.incoming
    ? urgent
    : (localsend && localsend.ready ? barForeground : Qt.darker(barForeground, 1.65))
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool payloadReady: localsend && localsend.payloadKind !== ""
  readonly property var nearbyDevices: {
    var list = []
    if (!localsend || !(localsend.devices instanceof Array)) return list
    for (var i = 0; i < localsend.devices.length; i++) {
      var device = localsend.devices[i]
      if (device && device.online === true) list.push(device)
    }
    return list
  }
  readonly property var visibleTransfers: {
    if (!localsend || !(localsend.transfers instanceof Array)) return []
    return localsend.transfers.slice(0, 6)
  }

  function closeForChooser(kind) {
    close()
    if (!localsend) return
    if (kind === "folder") localsend.chooseFolder()
    else localsend.chooseFiles()
  }

  function deviceGlyph(type) {
    var value = String(type || "")
    if (value === "mobile") return "󰄜"
    if (value === "desktop") return "󰍹"
    if (value === "web") return "󰖟"
    if (value === "server") return "󰒋"
    return "󰇄"
  }

  function stateLabel(state) {
    var value = String(state || "")
    if (value === "preparing") return "WAITING"
    if (value === "transferring") return "TRANSFERRING"
    if (value === "cancelling") return "CANCELLING"
    if (value === "completed") return "COMPLETE"
    if (value === "declined") return "DECLINED"
    if (value === "cancelled") return "CANCELLED"
    if (value === "failed") return "FAILED"
    return value.toUpperCase()
  }

  function transferTitle(transfer) {
    if (!transfer) return "Transfer"
    var files = transfer.files instanceof Array ? transfer.files : []
    var count = Number(transfer.fileCount || files.length || 0)
    if (count === 1 && files.length > 0) return String(files[0].name || "1 item")
    return count + (count === 1 ? " item" : " items")
  }

  function transferMeta(transfer) {
    if (!transfer) return ""
    var direction = String(transfer.direction || "") === "incoming" ? "FROM " : "TO "
    var alias = transfer.peer ? String(transfer.peer.alias || "Unknown device") : "Unknown device"
    return direction + alias + "  /  " + (localsend ? localsend.formatBytes(transfer.totalBytes) : "")
  }

  function transferProgress(transfer) {
    if (!transfer) return 0
    var total = Number(transfer.totalBytes || 0)
    if (total <= 0) return String(transfer.state || "") === "completed" ? 1 : 0
    return Math.max(0, Math.min(1, Number(transfer.completedBytes || 0) / total))
  }

  function isTransferActive(transfer) {
    var state = String(transfer && transfer.state || "")
    return state === "preparing" || state === "transferring" || state === "cancelling"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    if (localsend) localsend.queueSnapshot()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { if (root.localsend) root.localsend.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        LocalSendIcon {
          id: symbolicIcon
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor

          SequentialAnimation on opacity {
            running: root.localsend && root.localsend.incoming !== null
            loops: Animation.Infinite
            NumberAnimation { to: 0.48; duration: 650; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        if (root.localsend) root.localsend.refresh()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.localsend) return
        var key = String(text || "").toLowerCase()
        if (key === "r") root.localsend.refresh()
        else if (key === "f") root.closeForChooser("files")
        else if (key === "d") root.closeForChooser("folder")
        else if (key === "c") root.localsend.chooseClipboard()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.localsend && root.localsend.daemon.alias
              ? String(root.localsend.daemon.alias)
              : "LocalSend"
            meta: root.localsend && root.localsend.ready
              ? "RECEIVER READY"
              : (root.localsend ? String(root.localsend.phase || "STARTING") : "STARTING")
            detail: root.localsend ? root.localsend.onlineDeviceCount + " NEARBY" : "0 NEARBY"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.localsend && root.localsend.ready ? 1.0 : 0.48
            iconComponent: Component {
              Image {
                width: Style.space(54)
                height: Style.space(54)
                source: Quickshell.iconPath("localsend", true)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: root.localsend && root.localsend.daemon.refreshing ? "󰑓" : "󰑐"
                tooltipText: "Refresh nearby devices"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.localsend && root.localsend.ready && !root.localsend.busy
                onClicked: root.localsend.refresh()
              }
            }
          }

          Text {
            visible: root.localsend && (root.localsend.actionStatus !== "" || root.localsend.lastError !== "")
            width: parent.width
            text: root.localsend
              ? (root.localsend.actionStatus !== "" ? root.localsend.actionStatus : root.localsend.lastError)
              : ""
            color: root.localsend && root.localsend.actionStatus !== "" ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }

          Column {
            visible: root.localsend && root.localsend.incoming !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "INCOMING REQUEST"
              foreground: root.urgent
              fontFamily: root.fontFamily
            }

            BorderSurface {
              width: parent.width
              implicitHeight: incomingContent.implicitHeight + Style.space(24)
              color: Style.selectedFillFor(root.urgent, root.urgent)
              borderSpec: Border.flat(root.urgent, 1)
              radius: Style.cornerRadius

              Column {
                id: incomingContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(7)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(9)

                  Text {
                    text: "󰇚"
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: root.localsend && root.localsend.incoming
                        ? String(root.localsend.incoming.sender.alias || "Unknown device")
                        : "Unknown device"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      Layout.fillWidth: true
                      text: {
                        if (!root.localsend || !root.localsend.incoming) return ""
                        var request = root.localsend.incoming
                        var files = request.files instanceof Array ? request.files.length : 0
                        return request.messagePreview !== null && request.messagePreview !== undefined
                          ? "Wants to share clipboard text"
                          : files + (files === 1 ? " file" : " files") + "  /  " + root.localsend.formatBytes(request.totalBytes)
                      }
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }
                  }
                }

                Text {
                  visible: root.localsend && root.localsend.incoming && root.localsend.incoming.messagePreview !== null && root.localsend.incoming.messagePreview !== undefined
                  width: parent.width
                  text: visible ? String(root.localsend.incoming.messagePreview || "") : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  DecisionButton {
                    width: (parent.width - parent.spacing) / 2
                    label: "Decline"
                    foreground: root.urgent
                    enabled: root.localsend && !root.localsend.busy
                    onClicked: if (root.localsend && root.localsend.incoming) root.localsend.declineRequest(root.localsend.incoming.id)
                  }

                  DecisionButton {
                    width: (parent.width - parent.spacing) / 2
                    label: "Accept"
                    foreground: root.foreground
                    filled: true
                    enabled: root.localsend && !root.localsend.busy
                    onClicked: if (root.localsend && root.localsend.incoming) root.localsend.acceptRequest(root.localsend.incoming.id)
                  }
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(9)

            PanelSectionHeader {
              text: "CHOOSE WHAT TO SHARE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(7)

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰈔"
                label: "Files"
                enabled: root.localsend && root.localsend.ready && !root.localsend.choosing
                selected: root.localsend && root.localsend.payloadKind === "files" && root.localsend.selectedPaths.length > 1
                onClicked: root.closeForChooser("files")
              }

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰉋"
                label: "Folder"
                enabled: root.localsend && root.localsend.ready && !root.localsend.choosing
                selected: root.localsend && root.localsend.payloadKind === "files" && root.localsend.selectedPaths.length === 1 && String(root.localsend.payloadLabel).indexOf("Folder:") === 0
                onClicked: root.closeForChooser("folder")
              }

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰅇"
                label: "Clipboard"
                enabled: root.localsend && root.localsend.ready
                selected: root.localsend && root.localsend.payloadKind === "clipboard"
                onClicked: if (root.localsend) root.localsend.chooseClipboard()
              }
            }

            BorderSurface {
              visible: root.payloadReady
              width: parent.width
              implicitHeight: payloadRow.implicitHeight + Style.space(14)
              color: Style.selectedFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              RowLayout {
                id: payloadRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(7)
                spacing: Style.space(8)

                Text {
                  text: "󰒊"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  Layout.fillWidth: true
                  text: root.localsend ? root.localsend.payloadLabel : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideMiddle
                  textFormat: Text.PlainText
                }

                PanelActionButton {
                  iconText: "󰅖"
                  tooltipText: "Clear selection"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.localsend.clearPayload()
                }
              }
            }

            Text {
              width: parent.width
              text: root.payloadReady
                ? "Select a nearby device to send now."
                : "Pick files, a folder, or clipboard text first."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "NEARBY DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.nearbyDevices.length === 0
              width: parent.width
              text: root.localsend && root.localsend.ready
                ? "No nearby devices found."
                : "Starting the LocalSend receiver..."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.nearbyDevices

                DeviceRow {
                  required property var modelData
                  width: parent.width
                  device: modelData
                }
              }
            }
          }

          PanelSeparator {
            visible: root.visibleTransfers.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.visibleTransfers.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "ACTIVITY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visibleTransfers

                TransferRow {
                  required property var modelData
                  width: parent.width
                  transfer: modelData
                }
              }
            }
          }

          Text {
            visible: !!(root.localsend && root.localsend.daemon.destination)
            width: parent.width
            text: visible ? "Incoming files save to " + String(root.localsend.daemon.destination) : ""
            color: Qt.darker(root.dim, 1.18)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
          }
        }
      }
    }
  }

  component ActionTile: CursorSurface {
    id: tile

    property string iconText: ""
    property string label: ""
    property bool selected: false
    signal clicked()

    foreground: root.foreground
    current: selected
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
    implicitHeight: Style.space(62)

    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.iconText
        color: tile.enabled ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.label
        color: tile.enabled ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: tile.selected
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: tile.enabled
      cursorShape: tile.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: tile.clicked()
    }
  }

  component DecisionButton: BorderSurface {
    id: decision

    property string label: ""
    property color foreground: root.foreground
    property bool filled: false
    signal clicked()

    implicitHeight: Style.space(36)
    color: filled
      ? (mouse.containsMouse ? Style.focusFillFor(foreground, Color.accent) : Style.selectedFillFor(foreground, Color.accent))
      : (mouse.containsMouse ? Style.hoverFillFor(foreground, Color.accent) : "transparent")
    borderSpec: Border.controlSpec(mouse.containsMouse ? "hover-cursor" : "normal", foreground, Color.accent)
    radius: Style.cornerRadius
    opacity: enabled ? 1.0 : 0.45

    Text {
      anchors.centerIn: parent
      text: decision.label
      color: decision.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: decision.enabled
      cursorShape: decision.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: decision.clicked()
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow

    property var device: null
    readonly property string alias: device ? String(device.alias || "Unknown device") : "Unknown device"
    readonly property string subtitle: {
      if (!device) return ""
      var parts = []
      if (device.model) parts.push(String(device.model))
      if (device.type) parts.push(String(device.type).toUpperCase())
      if (parts.length === 0 && device.address) parts.push(String(device.address.host || ""))
      return parts.join("  /  ")
    }

    foreground: root.foreground
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    implicitHeight: Style.space(54)

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(9)

      Text {
        text: root.deviceGlyph(deviceRow.device ? deviceRow.device.type : "")
        color: root.payloadReady ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: deviceRow.alias
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: root.payloadReady
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          Layout.fillWidth: true
          text: deviceRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      BorderSurface {
        implicitWidth: sendLabel.implicitWidth + Style.space(16)
        implicitHeight: Style.space(28)
        color: root.payloadReady ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
        borderSpec: root.payloadReady ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none()
        radius: Style.cornerRadius

        Text {
          id: sendLabel
          anchors.centerIn: parent
          text: root.payloadReady ? "SEND" : "SELECT"
          color: root.payloadReady ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: root.payloadReady && root.localsend && !root.localsend.busy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (deviceRow.device) root.localsend.sendToDevice(deviceRow.device.fingerprint)
    }
  }

  component TransferRow: CursorSurface {
    id: transferRow

    property var transfer: null
    readonly property bool active: root.isTransferActive(transfer)
    readonly property real progress: root.transferProgress(transfer)
    readonly property bool failed: transfer && String(transfer.state || "") === "failed"
    readonly property var paths: root.localsend ? root.localsend.transferPaths(transfer) : []
    readonly property bool openable: paths.length > 0

    foreground: root.foreground
    // This panel carries no keyboard cursor, so a received row owns its own
    // hover paint. Only one row can hold the pointer, which is the single
    // highlight CursorSurface exists to draw.
    hasCursor: openable && rowMouse.containsMouse
    implicitHeight: transferBody.implicitHeight + Style.space(16)

    // Declared before the row content so the cancel button sitting on top of
    // it keeps its own clicks.
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: transferRow.openable
      acceptedButtons: Qt.LeftButton
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(mouse) {
        if (!root.localsend || !transferRow.transfer) return
        if (mouse.modifiers & Qt.AltModifier) root.localsend.revealTransfer(transferRow.transfer)
        else root.localsend.openTransfer(transferRow.transfer)
        root.close()
      }

      PanelToolTip {
        visible: transferRow.openable && rowMouse.containsMouse
        text: transferRow.paths.length > 1
          ? "Open the folder  /  Alt+click to select the files in it"
          : "Open the file  /  Alt+click to show it in its folder"
        fontFamily: root.fontFamily
      }
    }

    Column {
      id: transferBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(5)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: transfer && String(transfer.direction || "") === "incoming" ? "󰁅" : "󰁝"
          color: transferRow.failed ? root.urgent : (transferRow.active ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            Layout.fillWidth: true
            text: root.transferTitle(transferRow.transfer)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
          }

          Text {
            Layout.fillWidth: true
            text: root.transferMeta(transferRow.transfer)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
        }

        Text {
          text: root.stateLabel(transfer ? transfer.state : "")
          color: transferRow.failed ? root.urgent : (transferRow.active ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.6
        }

        PanelActionButton {
          visible: transferRow.active
          iconText: "󰜺"
          tooltipText: "Cancel transfer"
          foreground: root.foreground
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          enabled: root.localsend && !root.localsend.busy && transfer && String(transfer.state || "") !== "cancelling"
          onClicked: if (transferRow.transfer) root.localsend.cancelTransfer(transferRow.transfer.id)
        }
      }

      Rectangle {
        visible: transferRow.active || transferRow.progress > 0
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: Qt.darker(root.foreground, 2.2)

        Rectangle {
          width: parent.width * transferRow.progress
          height: parent.height
          radius: parent.radius
          color: transferRow.failed ? root.urgent : root.foreground
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        }
      }
    }
  }
}
