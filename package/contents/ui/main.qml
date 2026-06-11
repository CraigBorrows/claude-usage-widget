import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- config ----
    readonly property string cmd: "/home/bash/.local/bin/claude-usage-json"
    readonly property int pollMs: 60000

    // ---- state (from the official OAuth usage endpoint) ----
    property var fiveHour: null        // {util, resets_ms}  — current session window
    property var sevenDay: null        // weekly, all models
    property var sevenDayOpus: null    // weekly, Opus       (may be null)
    property var sevenDaySonnet: null  // weekly, Sonnet     (may be null)
    property string errorMsg: ""
    property double nowMs: 0           // ticks every second for live countdowns

    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: "Claude Usage"
    toolTipSubText: fiveHour
        ? ("Session " + Math.round(fiveHour.util) + "% · resets in " + remainStr(fiveHour.resets_ms)
           + (sevenDay ? ("\nWeekly " + Math.round(sevenDay.util) + "%") : ""))
        : (errorMsg !== "" ? statusText() : "No data")

    // ---------- data fetch ----------
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            if (data["exit code"] !== 0) { root.errorMsg = "exec"; return }
            try {
                var p = JSON.parse(data["stdout"])
                if (p.error) {
                    root.errorMsg = p.error
                    root.fiveHour = root.sevenDay = root.sevenDayOpus = root.sevenDaySonnet = null
                    return
                }
                root.fiveHour = p.five_hour
                root.sevenDay = p.seven_day
                root.sevenDayOpus = p.seven_day_opus
                root.sevenDaySonnet = p.seven_day_sonnet
                root.errorMsg = ""
            } catch (e) {
                root.errorMsg = "parse"
            }
        }
        function poll() { connectSource(root.cmd) }
    }

    Timer { interval: root.pollMs; running: true; repeat: true; triggeredOnStart: true; onTriggered: exec.poll() }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.nowMs = new Date().getTime() }

    // ---------- helpers ----------
    function remainStr(resetMs) {
        if (!resetMs) return "—"
        var ms = Math.max(0, resetMs - nowMs)
        var totalMin = Math.floor(ms / 60000)
        var d = Math.floor(totalMin / 1440)
        var h = Math.floor((totalMin % 1440) / 60)
        var m = totalMin % 60
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h" + (m < 10 ? "0" : "") + m + "m"
        return m + "m"
    }
    function resetAtStr(resetMs) {
        if (!resetMs) return ""
        return Qt.formatDateTime(new Date(resetMs), "ddd d MMM, h:mm ap")
    }
    function utilColor(u) {
        if (u === undefined || u === null) return Kirigami.Theme.textColor
        if (u >= 90) return Kirigami.Theme.negativeTextColor
        if (u >= 70) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }
    function statusText() {
        if (errorMsg === "no-token" || errorMsg === "http-401") return "Sign in to Claude"
        if (errorMsg === "net" || errorMsg === "exec") return "Offline"
        return "Error"
    }

    // ---------- compact (in-panel): just text, % above, time below ----------
    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: col.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: col.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: col.implicitHeight
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: 0

            PlasmaComponents3.Label {   // session % — headline
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: root.fiveHour ? (Math.round(root.fiveHour.util) + "%") : "—"
                color: root.fiveHour ? root.utilColor(root.fiveHour.util) : Kirigami.Theme.disabledTextColor
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.1)
                font.features: { "tnum": 1 }
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
            }
            PlasmaComponents3.Label {   // time until reset — below
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: root.fiveHour ? root.remainStr(root.fiveHour.resets_ms)
                                    : (root.errorMsg !== "" ? "!" : "…")
                opacity: 0.8
                font.pixelSize: Math.round(Kirigami.Theme.smallFont.pixelSize)
                font.features: { "tnum": 1 }
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 7
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ---------- full (popup) ----------
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 15

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading { level: 3; text: "Claude Usage" }

            // ---- current session (5h) ----
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.fiveHour !== null
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label { text: "Current session"; opacity: 0.8 }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: root.fiveHour ? (Math.round(root.fiveHour.util) + "%") : "—"
                        font.bold: true
                        color: root.fiveHour ? root.utilColor(root.fiveHour.util) : Kirigami.Theme.textColor
                    }
                }
                PlasmaComponents3.ProgressBar {
                    Layout.fillWidth: true; from: 0; to: 100
                    value: root.fiveHour ? root.fiveHour.util : 0
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: root.fiveHour ? ("Resets in " + root.remainStr(root.fiveHour.resets_ms)
                                           + " · " + root.resetAtStr(root.fiveHour.resets_ms)) : ""
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            Kirigami.Separator { Layout.fillWidth: true; visible: root.fiveHour !== null }

            // ---- weekly limits ----
            Kirigami.Heading {
                level: 4; text: "Weekly limits"
                visible: root.sevenDay !== null
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.sevenDay !== null
                spacing: Kirigami.Units.largeSpacing

                // weekly row factory via Repeater
                Repeater {
                    model: [
                        { label: "All models", d: root.sevenDay },
                        { label: "Opus",       d: root.sevenDayOpus },
                        { label: "Sonnet",     d: root.sevenDaySonnet }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        visible: modelData.d !== null && modelData.d !== undefined
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents3.Label { text: modelData.label; opacity: 0.8 }
                            Item { Layout.fillWidth: true }
                            PlasmaComponents3.Label {
                                text: modelData.d ? (Math.round(modelData.d.util) + "%") : "—"
                                font.bold: true
                                color: modelData.d ? root.utilColor(modelData.d.util) : Kirigami.Theme.textColor
                            }
                        }
                        PlasmaComponents3.ProgressBar {
                            Layout.fillWidth: true; from: 0; to: 100
                            value: modelData.d ? modelData.d.util : 0
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: modelData.d && modelData.d.resets_ms
                            text: modelData.d && modelData.d.resets_ms
                                  ? ("Resets " + root.resetAtStr(modelData.d.resets_ms)
                                     + " (" + root.remainStr(modelData.d.resets_ms) + ")") : ""
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }

            // ---- error / signed-out state ----
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.fiveHour === null
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: root.errorMsg === "no-token" || root.errorMsg === "http-401"
                      ? "Not signed in.\nRun Claude Code to refresh your session."
                      : (root.errorMsg !== "" ? ("Couldn't reach the usage API (" + root.errorMsg + ").")
                                              : "Loading…")
            }

            Item { Layout.fillHeight: true }
        }
    }
}
