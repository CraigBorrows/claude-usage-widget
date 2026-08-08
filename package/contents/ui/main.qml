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
    // Helper ships inside the package; resolve its path relative to this file
    // so the widget works on any machine (no hardcoded home path).
    readonly property string scriptPath: Qt.resolvedUrl("../code/claude-usage.py").toString().replace(/^file:\/\//, "")
    readonly property string cmd: "python3 '" + scriptPath + "'"
    readonly property int pollMs: 60000

    // ---- state (from the official OAuth usage endpoint) ----
    property var fiveHour: null        // {util, resets_ms}  — current session window
    property var sevenDay: null        // weekly, all models
    property var limits: []            // full limit list incl. per-model weekly caps
    property var extra: null           // extra usage credits, when enabled
    property string errorMsg: ""
    property double nowMs: 0           // ticks every 15s for live countdowns
    property double lastFetchMs: 0     // when the last successful fetch landed
    property bool busy: false          // a fetch is in flight
    property int fetchSeq: 0           // makes each run a distinct DataSource source

    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: "Claude Usage"
    toolTipSubText: fiveHour
        ? ("Session " + Math.round(fiveHour.util) + "% · resets in " + remainStr(fiveHour.resets_ms)
           + (sevenDay ? ("\nWeekly " + Math.round(sevenDay.util) + "%") : "")
           + "\nMiddle-click to refresh")
        : (errorMsg !== "" ? statusText() : "No data")

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Refresh now"
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    // ---------- data fetch ----------
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.busy = false
            if (data["exit code"] !== 0) { root.errorMsg = "exec"; return }
            try {
                var p = JSON.parse(data["stdout"])
                if (p.error) {
                    root.errorMsg = p.error
                    // Only blank the data on genuine auth loss. Transient errors
                    // (rate limit, network blip) keep the last-known values so
                    // the widget degrades gracefully instead of flickering empty.
                    if (p.error === "no-token" || p.error === "http-401") {
                        root.fiveHour = root.sevenDay = null
                        root.limits = []
                        root.extra = null
                    }
                    return
                }
                root.fiveHour = p.five_hour
                root.sevenDay = p.seven_day
                root.limits = p.limits ? p.limits : []
                root.extra = p.extra
                root.lastFetchMs = p.fetched_ms ? p.fetched_ms : new Date().getTime()
                root.errorMsg = ""
            } catch (e) {
                root.errorMsg = "parse"
            }
        }
    }

    // Force a fetch right now. The trailing shell comment gives every run a
    // distinct source name, so a manual refresh always re-executes instead of
    // being swallowed as a duplicate of the source already connected.
    //
    // The counter WRAPS, and must. Plasma5Support exposes source names through a
    // QQmlPropertyMap backed by a QQmlOpenMetaObject, which is append-only: every
    // name ever used stays a property forever, and each connect/disconnect calls
    // QMetaObjectBuilder::toMetaObject() to rebuild the metaobject over all of
    // them, so an unbounded counter turns every poll into O(polls so far). The
    // 3 s siblings (cpu-widget, memory-widget) pinned plasmashell's main thread
    // at 100% this way; at 60 s this one is slower to bite but grows just the
    // same. 8 names means one is reused only after 8 minutes.
    function refresh() {
        root.busy = true
        root.fetchSeq = (root.fetchSeq + 1) % 8
        root.nowMs = new Date().getTime()
        exec.connectSource(root.cmd + " # " + root.fetchSeq)
    }

    Timer { interval: root.pollMs; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.nowMs = new Date().getTime() }
    // Watchdog: the helper self-limits to a 10s HTTP timeout, so anything past
    // 20s means the run is gone — clear the spinner rather than wedge on it.
    Timer {
        interval: 20000; running: root.busy; repeat: false
        onTriggered: root.busy = false
    }

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
    function agoStr(ms) {
        if (!ms) return "never"
        var mins = Math.floor(Math.max(0, nowMs - ms) / 60000)
        if (mins < 1) return "just now"
        if (mins < 60) return mins + "m ago"
        return Math.floor(mins / 60) + "h ago"
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
    // Weekly rows, newest API shape first (per-model caps live in `limits`),
    // falling back to the flat seven_day field on older responses.
    function weeklyRows() {
        var rows = []
        for (var i = 0; i < limits.length; ++i) {
            var l = limits[i]
            if (l.group === "weekly") rows.push(l)
        }
        if (rows.length === 0 && sevenDay) {
            rows.push({ label: "All models", util: sevenDay.util,
                        resets_ms: sevenDay.resets_ms, is_active: false })
        }
        return rows
    }

    // ---------- compact (in-panel): just text, % above, time below ----------
    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: col.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: col.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: col.implicitHeight
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) root.refresh()
            else root.expanded = !root.expanded
        }

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
                opacity: root.busy ? 0.45 : 0.8
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
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // ---- header: title + refresh ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading { level: 3; text: "Claude Usage" }
                Item { Layout.fillWidth: true }

                PlasmaComponents3.Label {
                    text: root.busy ? "Refreshing…" : ("Updated " + root.agoStr(root.lastFetchMs))
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents3.BusyIndicator {
                    running: root.busy
                    visible: root.busy
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: "Refresh now"
                    enabled: !root.busy
                    onClicked: root.refresh()
                    PlasmaComponents3.ToolTip.text: "Fetch usage now"
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

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
                visible: root.weeklyRows().length > 0
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.weeklyRows().length > 0
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: root.weeklyRows()
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents3.Label { text: modelData.label; opacity: 0.8 }
                            PlasmaComponents3.Label {
                                text: "· in use"
                                visible: modelData.is_active === true
                                opacity: 0.55
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                            Item { Layout.fillWidth: true }
                            PlasmaComponents3.Label {
                                text: (modelData.util !== null && modelData.util !== undefined)
                                      ? (Math.round(modelData.util) + "%") : "—"
                                font.bold: true
                                color: root.utilColor(modelData.util)
                            }
                        }
                        PlasmaComponents3.ProgressBar {
                            Layout.fillWidth: true; from: 0; to: 100
                            value: modelData.util ? modelData.util : 0
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: !!modelData.resets_ms
                            text: modelData.resets_ms
                                  ? ("Resets " + root.resetAtStr(modelData.resets_ms)
                                     + " (" + root.remainStr(modelData.resets_ms) + ")") : ""
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }

            // ---- extra usage credits (only when enabled on the account) ----
            RowLayout {
                Layout.fillWidth: true
                visible: root.extra !== null && root.extra !== undefined
                PlasmaComponents3.Label { text: "Extra usage"; opacity: 0.8 }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Label {
                    text: root.extra
                          ? ((root.extra.used !== null && root.extra.used !== undefined
                              ? (root.extra.used.toFixed(2) + " " + (root.extra.currency || ""))
                              : "")
                             + (root.extra.util !== null && root.extra.util !== undefined
                                ? (" · " + Math.round(root.extra.util) + "%") : ""))
                          : ""
                    font.bold: true
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
