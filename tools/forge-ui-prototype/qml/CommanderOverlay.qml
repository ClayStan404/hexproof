// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
import QtQuick
import QtQuick.Layouts
import "FixtureData.js" as Fixtures

Item {
    id: root
    required property var model
    property string assetRoot: ""
    property real unit: 1
    signal inspected(var card)
    readonly property Item primaryButton: primary
    readonly property Item cancelButton: secondary
    readonly property string heading: model.state === "payment" ? "Pay for your commander"
        : model.state === "return" ? "Return your commander?"
        : model.state === "stack" ? "Isamaru is on the stack"
        : model.state === "battlefield" ? "Isamaru entered the battlefield"
        : model.state === "finished" ? "Commander destination chosen" : "Your commander is available"

    function primaryAction() {
        if (model.state === "ready") model.cast()
        else if (model.state === "payment") model.pay()
        else if (model.state === "stack") model.resolve()
        else if (model.state === "return") model.destination("command")
    }
    Row {
        x: 27 * root.unit; y: 122 * root.unit
        spacing: 5 * root.unit
        StudyButton {
            objectName: "studyDuelCastExample"
            text: "Casting"; unit: root.unit
            implicitWidth: 104 * root.unit; implicitHeight: 31 * root.unit
            quiet: true
            onClicked: root.model.reset("cast")
        }
        StudyButton {
            objectName: "studyDuelReturnExample"
            text: "Zone choice"; unit: root.unit
            implicitWidth: 130 * root.unit; implicitHeight: 31 * root.unit
            quiet: true
            onClicked: root.model.reset("return")
        }
    }
    StudyLabel {
        x: 28 * root.unit; y: 104 * root.unit
        text: "DUEL COMMANDER EXAMPLES"
        pointSize: 8; unit: root.unit; font.letterSpacing: 1; color: "#92a9b5"
    }
    Rectangle {
        x: (parent.width - width) / 2
        y: 69 * root.unit
        width: 640 * root.unit
        height: 76 * root.unit
        radius: 10 * root.unit
        color: "#f1192934"
        border.color: "#a28d68"
        Image {
            x: 9 * root.unit; y: 9 * root.unit
            width: 76 * root.unit; height: 58 * root.unit
            source: root.assetRoot ? root.assetRoot + "isamaru-art.jpg" : ""
            fillMode: Image.PreserveAspectCrop
        }
        Column {
            x: 101 * root.unit; y: 14 * root.unit
            spacing: 8 * root.unit
            StudyLabel { text: root.heading; pointSize: 17; unit: root.unit; color: "#ead8b4" }
            StudyLabel {
                text: root.model.state === "payment" ? "Mana cost W  +  commander tax 2  =  total 2 W"
                    : root.model.state === "return" ? "Isamaru is in your graveyard. Move it to the command zone?"
                    : root.model.state === "ready" ? "Cast Isamaru from the command zone when you have priority."
                    : "The commander panel keeps its location and cast count visible."
                pointSize: 11; unit: root.unit
            }
        }
    }
    CommanderZone {
        x: 28 * root.unit; y: 160 * root.unit
        card: Fixtures.opposingCommander()
        caption: "OPPONENT'S COMMANDER"
        controlName: "studyCommanderOpponent"
        location: "command"; cost: "1 W"; tax: "+0"; castCount: 0
        assetRoot: root.assetRoot; unit: root.unit
        onInspected: card => root.inspected(card)
    }
    CommanderZone {
        x: 28 * root.unit; y: 460 * root.unit
        card: root.model.commander
        location: root.model.location
        cost: root.model.nextCost
        tax: root.model.additionalCost
        castCount: root.model.castCount
        actionable: root.model.state === "ready"
        assetRoot: root.assetRoot; unit: root.unit
        onActivated: root.model.cast()
        onInspected: card => root.inspected(card)
    }
    Rectangle {
        x: parent.width - width - 24 * root.unit
        y: parent.height - height - 26 * root.unit
        width: 308 * root.unit
        height: (root.model.state === "payment" ? 218 : 182) * root.unit
        radius: 13 * root.unit
        color: "#f114222c"
        border.color: "#a89064"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15 * root.unit
            spacing: 10 * root.unit
            StudyLabel { text: "DUEL COMMANDER"; pointSize: 11; unit: root.unit; color: "#dcc18e"; font.letterSpacing: 1 }
            StudyLabel {
                Layout.fillWidth: true
                text: root.model.state === "payment" ? "2 W  /  " + root.model.reserved.length + " of 3 mana selected"
                    : root.model.state === "return" ? "Returning it preserves the number of times it was cast."
                    : root.model.state === "stack" ? "Respond now, or resolve the commander."
                    : root.model.state === "ready" ? "Isamaru costs W plus 2 for its previous cast."
                    : root.model.state === "battlefield" ? "Commander on battlefield. Waiting for the next action."
                    : "Destination: " + (root.model.location === "command" ? "command zone" : "graveyard")
                pointSize: 13; unit: root.unit; wrapMode: Text.WordWrap
            }
            StudyButton {
                objectName: "studyCommanderAutoPay"
                visible: root.model.state === "payment"
                text: "Auto pay"
                unit: root.unit
                Layout.fillWidth: true
                onClicked: root.model.autoPay()
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                StudyButton {
                    id: secondary
                    objectName: "studyCommanderCancel"
                    visible: root.model.state === "payment" || root.model.state === "return"
                    text: root.model.state === "return" ? "Keep in graveyard" : "Cancel"
                    unit: root.unit
                    Layout.fillWidth: true
                    onClicked: {
                        if (root.model.state === "return") root.model.destination("graveyard")
                        else root.model.cancel()
                    }
                }
                StudyButton {
                    id: primary
                    objectName: "studyCommanderPrimary"
                    text: root.model.state === "ready" ? "Cast Isamaru"
                        : root.model.state === "payment" ? "Pay 2 W"
                        : root.model.state === "stack" ? "Resolve top"
                        : root.model.state === "return" ? "Command zone" : "Waiting"
                    enabled: root.model.state === "ready" || root.model.state === "stack"
                        || root.model.state === "return" || root.model.canPay
                    primary: true
                    unit: root.unit
                    Layout.fillWidth: true
                    onClicked: root.primaryAction()
                }
            }
        }
    }
}
