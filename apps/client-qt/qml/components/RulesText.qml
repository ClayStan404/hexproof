// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
pragma Singleton
import QtQuick

QtObject {
    // Translate only known engine UI templates. Card/rules text and inserted
    // player names stay literal; translated text never determines a response.
    function text(source) {
        if (!source) return source
        return String(source).split("\n").map(line => translateLine(line)).join("\n")
    }

    function isPlayOrDraw(kind, title, detail) {
        return kind === "chooseBoolean" && (title + "\n" + detail).split("\n")
            .some(line => line === "Would you like to play or draw?")
    }

    function title(kind, source, detail) {
        return isPlayOrDraw(kind, source, detail) ? qsTr("Choose play or draw") : text(source)
    }

    function choice(kind, label, title, detail) {
        if (isPlayOrDraw(kind, title, detail)) {
            if (label === "Play") return qsTr("Play first")
            if (label === "Draw") return qsTr("Draw first")
        }
        if (kind !== "chooseBoolean") return label
        switch (label) {
        case "OK": return qsTr("OK")
        case "Cancel": return qsTr("Cancel")
        case "Accept": return qsTr("Accept")
        case "Decline": return qsTr("Decline")
        case "Library": return qsTr("Library")
        case "Graveyard": return qsTr("Graveyard")
        case "Top": return qsTr("Top")
        case "Bottom": return qsTr("Bottom")
        case "Keep this hand": return qsTr("Keep this hand")
        case "View next hand": return qsTr("View next hand")
        default: return label
        }
    }

    function translateLine(source) {
        switch (source) {
        // Exact native-host and adapter headings are listed here so lupdate
        // and the strict translation audit can track every UI string.
        case "Confirm decision": return qsTr("Confirm decision")
        case "Choose an action": return qsTr("Choose an action")
        case "Opening hand": return qsTr("Opening hand")
        case "Pay mana": return qsTr("Pay mana")
        case "Choose a card or player": return qsTr("Choose a card or player")
        case "Choose cards": return qsTr("Choose cards")
        case "Choose cards to put back": return qsTr("Choose cards to put back")
        case "Look at these cards": return qsTr("Look at these cards")
        case "Choose an order": return qsTr("Choose an order")
        case "Sort cards into zones": return qsTr("Sort cards into zones")
        case "Choose targets": return qsTr("Choose targets")
        case "Declare attackers": return qsTr("Declare attackers")
        case "Declare blockers": return qsTr("Declare blockers")
        case "Choose combat damage order": return qsTr("Choose combat damage order")
        case "Assign combat damage": return qsTr("Assign combat damage")
        case "Choose yes or no": return qsTr("Choose yes or no")
        case "Choose a number": return qsTr("Choose a number")
        case "Name a card": return qsTr("Name a card")
        case "Choose colors": return qsTr("Choose colors")
        case "Choose options": return qsTr("Choose options")
        case "Forge decision required": return qsTr("Forge decision required")
        case "This decision type is not supported by this Hexproof build.":
            return qsTr("This decision type is not supported by this Hexproof build.")
        case "Choose a mana ability:": return qsTr("Choose a mana ability:")
        case "Choose optional costs": return qsTr("Choose optional costs")
        case "Choose cost order": return qsTr("Choose cost order")
        case "Select order for simultaneous abilities": return qsTr("Select order for simultaneous abilities")
        case "Reorder simultaneous abilities": return qsTr("Reorder simultaneous abilities")
        case "Select order for replacement effects": return qsTr("Select order for replacement effects")
        case "Reorder replacement effects": return qsTr("Reorder replacement effects")
        case "Would you like to play or draw?": return qsTr("Would you like to play or draw?")
        case "Do you want to keep your hand?": return qsTr("Do you want to keep your hand?")
        case "Do you want to scry?": return qsTr("Do you want to scry?")
        case "Review the cards in your hand. Keep this hand or view the next starting hand.":
            return qsTr("Review the cards in your hand. Keep this hand or view the next starting hand.")
        case "Do you want to discard your hand?": return qsTr("Do you want to discard your hand?")
        case "Do you want to exile all cards in your graveyard?": return qsTr("Do you want to exile all cards in your graveyard?")
        case "Do you want to exile all cards in your hand?": return qsTr("Do you want to exile all cards in your hand?")
        case "You have priority.": return qsTr("You have priority.")
        case "You have mana floating in your mana pool that could be lost if you pass priority now.":
            return qsTr("You have mana floating in your mana pool that could be lost if you pass priority now.")
        case "Click on your life total to pay life for phyrexian mana.":
            return qsTr("Click on your life total to pay life for phyrexian mana.")
        }
        let match
        if ((match = source.match(/^Mulligans taken: (\d+)$/)))
            return qsTr("Mulligans taken: %1").arg(match[1])
        if ((match = source.match(/^Choose exactly (\d+) card\(s\) to put on the bottom of your library\.$/)))
            return qsTr("Choose exactly %1 card(s) to put on the bottom of your library.").arg(match[1])
        if ((match = source.match(/^Choose exactly (\d+) card\(s\)\.$/)))
            return qsTr("Choose exactly %1 card(s).").arg(match[1])
        if ((match = source.match(/^Choose between (\d+) and (\d+) card\(s\)\.$/)))
            return I18n.formatRulesLog(qsTr("Choose between %1 and %2 card(s)."), match.slice(1))
        if ((match = source.match(/^(.+), you have won the coin toss\.$/)))
            return I18n.formatRulesLog(qsTr("%1, you have won the coin toss."), match.slice(1))
        if ((match = source.match(/^(.+), you lost the last game\.$/)))
            return I18n.formatRulesLog(qsTr("%1, you lost the last game."), match.slice(1))
        if ((match = source.match(/^(.+), you are going first!$/)))
            return I18n.formatRulesLog(qsTr("%1, you are going first!"), match.slice(1))
        if ((match = source.match(/^(.+) is going first\.$/)))
            return I18n.formatRulesLog(qsTr("%1 is going first."), match.slice(1))
        if ((match = source.match(/^(.+), you are going second\.$/)))
            return I18n.formatRulesLog(qsTr("%1, you are going second."), match.slice(1))
        if ((match = source.match(/^Starting hand (\d+) of (\d+)$/)))
            return I18n.formatRulesLog(qsTr("Starting hand %1 of %2"), match.slice(1))
        if ((match = source.match(/^Use triggered ability of (.+)\?$/)))
            return I18n.formatRulesLog(qsTr("Use triggered ability of %1?"), match.slice(1))
        if ((match = source.match(/^Put (.+) on the top of library or graveyard\?$/)))
            return I18n.formatRulesLog(qsTr("Put %1 on the top of library or graveyard?"), match.slice(1))
        if ((match = source.match(/^Put (.+) on the top or bottom of your library\?$/)))
            return I18n.formatRulesLog(qsTr("Put %1 on the top or bottom of your library?"), match.slice(1))
        if ((match = source.match(/^Do you want to pay (\d+) life\?$/)))
            return qsTr("Do you want to pay %1 life?").arg(match[1])
        if ((match = source.match(/^Pay (\d+) life$/)))
            return qsTr("Pay %1 life").arg(match[1])
        if ((match = source.match(/^Use floating ([WUBRGC]) mana$/)))
            return qsTr("Use floating %1 mana").arg(match[1])
        if ((match = source.match(/^Choose (\d+) card\(s\) to discard$/)))
            return qsTr("Choose %1 card(s) to discard").arg(match[1])
        if ((match = source.match(/^Pay Mana Cost: (.+)$/)))
            return I18n.formatRulesLog(qsTr("Pay Mana Cost: %1"), match.slice(1))
        if ((match = source.match(/^Priority: (.+)$/)))
            return I18n.formatRulesLog(qsTr("Priority: %1"), match.slice(1))
        if ((match = source.match(/^Turn: (\d+) \((.+)\)(?:  \[(Day|Night)\])?$/)))
            return I18n.formatRulesLog(qsTr("Turn: %1 (%2)"), [match[1], match[2]])
                + (match[3] ? "  [" + (match[3] === "Day" ? qsTr("Day") : qsTr("Night")) + "]" : "")
        if ((match = source.match(/^Phase: (.+)$/)))
            return I18n.formatRulesLog(qsTr("Phase: %1"), [phase(match[1])])
        if (source === "Stack: Empty") return qsTr("Stack: Empty")
        if ((match = source.match(/^Stack: (\d+) to Resolve\.$/)))
            return qsTr("Stack: %1 to resolve.").arg(match[1])
        if ((match = source.match(/^Storm Count: (\d+)$/)))
            return qsTr("Storm Count: %1").arg(match[1])
        if ((match = source.match(/^(.+) — (cast spell|play land|activate ability)$/))) {
            const action = match[2] === "cast spell" ? qsTr("Cast spell")
                : match[2] === "play land" ? qsTr("Play land") : qsTr("Activate ability")
            return I18n.formatRulesLog(qsTr("%1 — %2"), [match[1], action])
        }
        // Unknown effect descriptions retain their exact text and mana symbols.
        return source
    }

    function phase(source) {
        const phases = {
            "Untap step": "untap", "Upkeep step": "upkeep", "Draw step": "draw",
            "Main phase, precombat": "main1", "Beginning of Combat Step": "begin_combat",
            "Declare Attackers Step": "declare_attackers", "Declare Blockers Step": "declare_blockers",
            "Combat Damage Step": "combat_damage", "End of Combat Step": "end_combat",
            "Main phase, postcombat": "main2", "End step": "end", "Cleanup step": "cleanup"
        }
        if (source === "First Strike Damage Step") return qsTr("First strike combat damage")
        return Object.prototype.hasOwnProperty.call(phases, source) ? I18n.gamePhaseLabel(phases[source]) : source
    }
}
