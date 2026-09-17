// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma Singleton

import QtQuick

QtObject {
    function tr(source) {
        if (source === undefined || source === null)
            return source
        return qsTranslate("HexproofDynamic", String(source))
    }

    function formatLabel(format) {
        switch (String(format).toLowerCase()) {
        case "custom":
            return qsTr("Custom 1v1")
        case "standard":
            return qsTr("Standard")
        case "pioneer":
            return qsTr("Pioneer")
        case "modern":
            return qsTr("Modern")
        case "legacy":
            return qsTr("Legacy")
        case "vintage":
            return qsTr("Vintage")
        case "pauper":
            return qsTr("Pauper")
        case "duel":
        case "duel commander":
            return qsTr("Duel Commander")
        case "commander":
        case "edh":
            return qsTr("Commander")
        case "cube":
            return qsTr("Cube")
        case "commander_cube":
        case "commander_limited":
            return qsTr("Commander Cube")
        default:
            return format
        }
    }

    function deckFormatOptions() {
        return [
            {"label": formatLabel("modern"), "value": "modern",
             "tableMode": "modern"},
            {"label": formatLabel("commander"), "value": "commander",
             "tableMode": "edh"},
            {"label": formatLabel("duel"), "value": "duel",
             "tableMode": "duel"},
            {"label": formatLabel("legacy"), "value": "legacy",
             "tableMode": "modern"},
            {"label": formatLabel("standard"), "value": "standard",
             "tableMode": "modern"},
            {"label": formatLabel("pioneer"), "value": "pioneer",
             "tableMode": "modern"},
            {"label": formatLabel("pauper"), "value": "pauper",
             "tableMode": "modern"},
            {"label": formatLabel("vintage"), "value": "vintage",
             "tableMode": "modern"},
            {"label": formatLabel("cube"), "value": "cube",
             "tableMode": "modern"},
            {"label": formatLabel("custom"), "value": "custom",
             "tableMode": "modern"}
        ]
    }

    function tournamentFormatLabel(format) {
        switch (String(format).toLowerCase()) {
        case "standard":
            return qsTr("Standard")
        case "pioneer":
            return qsTr("Pioneer")
        case "modern":
            return qsTr("Modern")
        case "legacy":
            return qsTr("Legacy")
        case "vintage":
            return qsTr("Vintage")
        case "pauper":
            return qsTr("Pauper")
        case "duel commander":
            return qsTr("Duel Commander")
        case "cube":
            return qsTr("Cube")
        default:
            return format
        }
    }

    function playersLabel(players) {
        return players && players.length > 0
                ? players.join(" · ") : qsTr("Unknown players")
    }

    function count(noun, value) {
        if (noun === "deck")
            return qsTr("%n deck(s)", "", value)
        if (noun === "card")
            return qsTr("%n card(s)", "", value)
        if (noun === "seat")
            return qsTr("%n seat(s)", "", value)
        if (noun === "printing")
            return qsTr("%n printing(s)", "", value)
        if (noun === "result")
            return qsTr("%n result(s)", "", value)
        return String(value)
    }

    function cardCategory(category) {
        switch (category) {
        case "Artifact":
            return qsTr("Artifact")
        case "Battle":
            return qsTr("Battle")
        case "Creature":
            return qsTr("Creature")
        case "Enchantment":
            return qsTr("Enchantment")
        case "Instant":
            return qsTr("Instant")
        case "Land":
            return qsTr("Land")
        case "Planeswalker":
            return qsTr("Planeswalker")
        case "Sorcery":
            return qsTr("Sorcery")
        case "Other":
            return qsTr("Other")
        default:
            return tr(category)
        }
    }

    function status(source, resolveCardName) {
        if (!source)
            return source
        const exact = tr(source)
        if (exact !== source)
            return exact
        return patternedStatus(source, resolveCardName)
    }

    // Log kind is server-owned. Never reinterpret user chat as an engine
    // event, even when its text happens to look exactly like a rules message.
    function gameLog(kind, source, resolveCardName, actorName) {
        if (kind === "chat" || !source)
            return source
        if (kind === "create_emblem") {
            const match = source.match(/^(.+) created a (.+) emblem for (.+)\.$/)
            return match ? formatRulesLog(qsTr("%1 created a %2 emblem for %3."),
                                         [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), match[3]]) : source
        }
        if (kind === "remove_emblem") {
            const match = source.match(/^(.+) removed their (.+) emblem\.$/)
            return match ? formatRulesLog(qsTr("%1 removed their %2 emblem."),
                                         [match[1], libraryCardDescriptionLabel(match[2], resolveCardName)]) : source
        }
        if (kind === "commander_color") {
            const match = source.match(/^(.+) chose ([WUBRG]) for (.+) \((s\d+-c\d+)\)\.$/)
            if (!match) return source
            const colors = {
                W: qsTranslate("CardWorkbench", "White"), U: qsTranslate("CardWorkbench", "Blue"),
                B: qsTranslate("CardWorkbench", "Black"), R: qsTranslate("CardWorkbench", "Red"),
                G: qsTranslate("CardWorkbench", "Green")
            }
            return formatRulesLog(qsTr("%1 chose %2 for %3 (%4)."),
                                  [match[1], colors[match[2]], libraryCardDescriptionLabel(match[3], resolveCardName), match[4]])
        }
        if (String(kind).startsWith("rules_"))
            return rulesGameLog(kind, source, resolveCardName, actorName)
        return manualGameLog(kind, source, resolveCardName)
    }

    function manualGameLog(kind, source, resolveCardName) {
        let match
        switch (kind) {
        case "create_token":
            match = source.match(/^(.+) created a (.+) token\.$/)
            if (match)
                return formatStatus(qsTr("%1 created a %2 token."),
                                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName)])
            break
        case "remove_token":
            match = source.match(/^(.+) removed a face-down token from the battlefield\.$/)
            if (match)
                return qsTr("%1 removed a face-down token from the battlefield.").arg(match[1])
            match = source.match(/^(.+) removed token (.+) from the battlefield\.$/)
            if (match)
                return formatStatus(qsTr("%1 removed token %2 from the battlefield."),
                                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName)])
            break
        case "face_down":
            match = source.match(/^(.+) turned a battlefield card (face down|face up)\.$/)
            if (match)
                return (match[2] === "face down"
                        ? qsTr("%1 turned a battlefield card face down.")
                        : qsTr("%1 turned a battlefield card face up.")).arg(match[1])
            break
        case "discard_hand":
            match = source.match(/^(.+) discarded their hand \((\d+) cards\)\.$/)
            if (match)
                return formatStatus(qsTr("%1 discarded their hand (%2 cards)."), match.slice(1))
            break
        case "discard_random":
            match = source.match(/^(.+) randomly discarded (.+)\.$/)
            if (match)
                return formatStatus(qsTr("%1 randomly discarded %2."),
                                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName)])
            break
        case "move_library_cards":
            match = source.match(/^(.+) put (\d+) card\(s\) from the top of their library into (hand|battlefield|graveyard|exile)\.$/)
            if (match)
                return formatStatus(qsTr("%1 put %2 card(s) from the top of their library into %3."),
                                    [match[1], match[2], zoneLabel(match[3])])
            break
        case "recall_revealed":
            match = source.match(/^(.+) returned (\d+) revealed card\(s\) to hand\.$/)
            if (match)
                return formatStatus(qsTr("%1 returned %2 revealed card(s) to hand."), match.slice(1))
            break
        case "library_reorder":
            match = source.match(/^(.+) reordered the top (\d+) card\(s\) of their library\.$/)
            if (match)
                return formatStatus(qsTr("%1 reordered the top %2 card(s) of their library."), match.slice(1))
            break
        case "draw":
            match = source.match(/^(.+) declared Game (\d+) a draw\.$/)
            if (match)
                return formatStatus(qsTr("%1 declared Game %2 a draw."), match.slice(1))
            break
        case "restart":
            match = source.match(/^(.+) restarted Game (\d+)\.$/)
            if (match)
                return formatStatus(qsTr("%1 restarted Game %2."), match.slice(1))
            break
        case "roll":
            match = source.match(/^(.+) rolled (\[\d+(?:, \d+)*\]) on (\d+)d(\d+) \(total (\d+)\)\.$/)
            if (match)
                return formatStatus(qsTr("%1 rolled %2 on %3d%4 (total %5)."), match.slice(1))
            match = source.match(/^(.+) won the roll for Game (\d+)\.$/)
            if (match)
                return formatStatus(qsTr("%1 won the roll for Game %2."), match.slice(1))
            break
        case "coin":
            match = source.match(/^(.+) flipped (heads|tails)\.$/)
            if (match)
                return (match[2] === "heads" ? qsTr("%1 flipped heads.")
                                             : qsTr("%1 flipped tails.")).arg(match[1])
            break
        case "random_select":
            match = source.match(/^(.+) randomly selected (.+)\.$/)
            if (match) {
                // This legacy kind can name either a player or a card. Do not
                // look up arbitrary player names in the card catalog.
                return formatStatus(qsTr("%1 randomly selected %2."),
                                    [match[1], libraryCardDescriptionLabel(match[2])])
            }
            break
        case "result":
            if (source === "The Commander game ended with no remaining players.")
                return qsTr("The Commander game ended with no remaining players.")
            break
        case "combat":
            match = source.match(/^(.+) declared (\d+) attacker\(s\) toward a battlefield permanent controlled by (.+)\.$/)
            if (match)
                return formatStatus(qsTr("%1 declared %2 attacker(s) toward a battlefield permanent controlled by %3."), match.slice(1))
            break
        }
        return status(source, resolveCardName)
    }

    function rulesGameLog(kind, source, resolveCardName, actorName) {
        let match
        switch (kind) {
        case "rules_start":
            match = source.match(/^Game (\d+) started \(Forge rules\)\.$/)
            if (match)
                return qsTr("Game %1 started (Forge rules).").arg(match[1])
            break
        case "rules_phase":
            match = source.match(/^Turn (\d+): (.+) \((untap|upkeep|draw|main1|begin_combat|declare_attackers|declare_blockers|combat_damage|end_combat|main2|end|cleanup)\)\.$/)
            if (match)
                return formatRulesLog(qsTr("Turn %1: %2 (%3)."),
                                      [match[1], match[2], gamePhaseLabel(match[3])])
            break
        case "rules_life":
            match = source.match(/^(.+): life (-?\d+) → (-?\d+)\.$/)
            if (match)
                return formatRulesLog(qsTr("%1: life %2 → %3."), match.slice(1))
            break
        case "rules_status":
            match = source.match(/^(.+): (playing|lost|conceded)\.$/)
            if (match)
                return formatRulesLog(qsTr("%1: %2."),
                                      [match[1], rulesPlayerStatusLabel(match[2])])
            break
        case "rules_zone_count":
            match = source.match(/^(.+): (hand|library) count (\d+) → (\d+)\.$/)
            if (match)
                return formatRulesLog(qsTr("%1: %2 count %3 → %4."),
                                      [match[1], zoneLabel(match[2]), match[3], match[4]])
            break
        case "rules_card":
            // Keep the whole actor/card prefix intact: both names may contain
            // colons, so splitting that prefix would alter legitimate names.
            match = source.match(/^(.+) (in|left) (battlefield|graveyard|exile|command)\.$/)
            if (match) {
                const prefix = rulesCardDescription(match[1], resolveCardName, actorName)
                return formatRulesLog(match[2] === "in" ? qsTr("%1 is in %2.")
                                                       : qsTr("%1 left %2."),
                                      [prefix, zoneLabel(match[3])])
            }
            break
        case "rules_tap":
            match = source.match(/^(.+) (tapped|untapped)\.$/)
            if (match) {
                const prefix = rulesCardDescription(match[1], resolveCardName, actorName)
                return match[2] === "tapped" ? qsTr("%1 tapped.").arg(prefix)
                                             : qsTr("%1 untapped.").arg(prefix)
            }
            break
        case "rules_stack":
            match = source.match(/^(.+) put a spell or ability on the stack\.$/)
            if (match)
                return qsTr("%1 put a spell or ability on the stack.").arg(match[1])
            match = source.match(/^A spell or ability controlled by (.+) left the stack\.$/)
            if (match)
                return qsTr("A spell or ability controlled by %1 left the stack.").arg(match[1])
            break
        case "rules_result":
            if (source === "Game ended without a winner.")
                return qsTr("Game ended without a winner.")
            match = source.match(/^(.+) won the game\.$/)
            if (match)
                return qsTr("%1 won the game.").arg(match[1])
            break
        }
        return source
    }

    function rulesCardDescription(prefix, resolveCardName, actorName) {
        // The public seat identifies the actor even when either name contains
        // colons. Older entries without that context keep their original names.
        if (actorName && prefix.startsWith(actorName + ": "))
            return actorName + ": " + libraryCardDescriptionLabel(
                        prefix.slice(actorName.length + 2), resolveCardName)
        const hidden = ": a face-down card"
        return prefix.endsWith(hidden)
                ? prefix.slice(0, -hidden.length) + ": " + qsTr("a face-down card")
                : prefix
    }

    function formatRulesLog(template, values) {
        // A player's literal "%2" is a name, not another formatting token.
        return template.replace(/%([1-4])/g, function(token, index) {
            return values[Number(index) - 1]
        })
    }

    function rulesPlayerStatusLabel(playerStatus) {
        switch (playerStatus) {
        case "playing": return qsTr("Playing")
        case "lost": return qsTr("Lost")
        case "conceded": return qsTr("Conceded")
        default: return playerStatus
        }
    }

    function formatStatus(template, values) {
        // Replace template tokens once so literal tokens in names stay intact.
        return template.replace(/%([1-9][0-9]*)/g, function(token, index) {
            const position = Number(index) - 1
            return position < values.length ? String(values[position]) : token
        })
    }

    function patternedStatus(source, resolveCardName) {
        const artLocation = source.match(/^Card images were copied and verified\. Restart Hexproof to use the new location\. Original files were kept at ([\s\S]+)\.$/)
        if (artLocation) {
            return formatStatus(tr("Card images were copied and verified. Restart Hexproof to use the new location. Original files were kept at %1."), [artLocation[1]])
        }
        if (source === "Checking deck legality…")
            return qsTr("Checking deck legality…")
        if (source === "Card database required to verify deck legality.")
            return qsTr("Card database required to verify deck legality.")
        if (source === "Commander decks require exactly 100 main-deck cards.")
            return qsTr("Commander decks require exactly 100 main-deck cards.")
        if (source === "Commander decks cannot use a sideboard.")
            return qsTr("Commander decks cannot use a sideboard.")
        if (source === "Commander decks require one or two commanders.")
            return qsTr("Commander decks require one or two commanders.")
        if (source === "Main deck requires at least 60 cards.")
            return qsTr("Main deck requires at least 60 cards.")
        if (source === "Sideboard can contain at most 15 cards.")
            return qsTr("Sideboard can contain at most 15 cards.")
        if (source === "Cube cards must stay in the main pool.")
            return qsTr("Cube cards must stay in the main pool.")
        if (source === "Every Cube card needs an exact printing.")
            return qsTr("Every Cube card needs an exact printing.")
        if (source === "Card printings unresolved. Install the card database or select printings.")
            return qsTr("Card printings unresolved. Install the card database or select printings.")
        if (source === "Could not open the legacy Cube library for migration.")
            return qsTr("Could not open the legacy Cube library for migration.")
        if (source === "The legacy Cube library could not be migrated and was left unchanged.")
            return qsTr("The legacy Cube library could not be migrated and was left unchanged.")
        if (source === "A legacy Cube conflicts with an existing deck and was left unchanged.")
            return qsTr("A legacy Cube conflicts with an existing deck and was left unchanged.")
        if (source === "Legacy Cubes were imported, but their source file could not be archived.")
            return qsTr("Legacy Cubes were imported, but their source file could not be archived.")
        let match = source.match(
                    /^The Cube needs at least (\d+) physical cards for a two-player draft\.$/)
        if (match) {
            return qsTr("The Cube needs at least %1 physical cards for a two-player draft.")
                    .arg(match[1])
        }
        match = source.match(/^(.+) is missing from the local card database\.$/)
        if (match)
            return qsTr("%1 is missing from the local card database.").arg(match[1])
        match = source.match(/^(.+) is not legal in (.+)\.$/)
        if (match)
            return formatStatus(qsTr("%1 is not legal in %2."),
                    [match[1], match[2]])
        match = source.match(/^(.+) is restricted to one copy in Vintage\.$/)
        if (match)
            return qsTr("%1 is restricted to one copy in Vintage.").arg(match[1])
        match = source.match(/^(.+) has (\d+) copies; commander formats are singleton\.$/)
        if (match) {
            return formatStatus(qsTr("%1 has %2 copies; commander formats are singleton."),
                    [match[1], match[2]])
        }
        match = source.match(/^(.+) has (\d+) copies; this format allows at most four\.$/)
        if (match) {
            return formatStatus(qsTr("%1 has %2 copies; this format allows at most four."),
                    [match[1], match[2]])
        }
        match = source.match(/^(.+) is outside the commanders' color identity\.$/)
        if (match)
            return qsTr("%1 is outside the commanders' color identity.").arg(match[1])
        match = source.match(/^(\d+) cards? may be outside the commanders' color identity\.$/)
        if (match) {
            return qsTr("%n card(s) may be outside the commanders' color identity.",
                        "", Number(match[1]))
        }
        match = source.match(/^(\d+) images? missing$/)
        if (match)
            return qsTr("%n image(s) missing", "", Number(match[1]))
        match = source.match(
                    /^The selected card database uses schema version (\d+), but this Hexproof version requires schema version (\d+)\.$/)
        if (match) {
            return qsTr(
                        "The selected card database uses schema version %1, but this Hexproof version requires schema version %2.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(/^(tournament_[a-z_]+):/)
        if (match) {
            switch (match[1]) {
            case "tournament_invalid":
                return qsTr("That action is not valid in the tournament's current state.")
            case "tournament_forbidden":
                return qsTr("You do not have permission to perform that tournament action.")
            case "tournament_not_found":
                return qsTr("The tournament or pairing no longer exists.")
            case "tournament_full":
                return qsTr("The tournament is full.")
            case "tournament_already_registered":
                return qsTr("That display name is already registered.")
            case "tournament_registration_closed":
                return qsTr("Tournament registration is closed.")
            case "tournament_not_ready":
                var countMatch = source.match(/at least (\d+) checked-in players/)
                if (countMatch)
                    return qsTr("At least %1 checked-in players are required.")
                            .arg(countMatch[1])
                return qsTr("The tournament is not ready for that action.")
            case "tournament_round_incomplete":
                return qsTr("Confirm every table result before advancing the round.")
            case "tournament_result_invalid":
                return qsTr("That match result is not valid for this pairing.")
            }
        }
        match = source.match(/^(\d+) main · (\d+) side(?: · (.+))?$/)
        if (match) {
            return formatStatus(qsTr("%1 main · %2 side"),
                    [match[1], match[2]])
                   + (match[3] ? " · " + match[3] : "")
        }
        match = source.match(
                    /^(\d+) cards · Drag a card here from the sideboard$/)
        if (match) {
            return qsTr(
                        "%n cards · Drag a card here from the sideboard",
                        "", Number(match[1]))
        }
        match = source.match(
                    /^(\d+) cards · Drop main-deck cards here$/)
        if (match) {
            return qsTr("%n cards · Drop main-deck cards here",
                        "", Number(match[1]))
        }
        match = source.match(/^(.+) installed locally$/)
        if (match)
            return qsTr("%1 installed locally").arg(match[1])
        match = source.match(/^(\d+) of (\d+) seats filled$/)
        if (match)
            return formatStatus(qsTr("%1 of %2 seats filled"),
                    [match[1], match[2]])
        match = source.match(/^Remove (.+)\?$/)
        if (match)
            return qsTr("Remove %1?").arg(match[1])
        match = source.match(/^Delete (.+)\?$/)
        if (match)
            return qsTr("Delete %1?").arg(match[1])
        match = source.match(
                    /^Connected as (.+)\. Choose how you want to play\.$/)
        if (match) {
            return qsTr("Connected as %1. Choose how you want to play.")
                    .arg(match[1])
        }
        match = source.match(/^(\d+) local decks?$/)
        if (match)
            return qsTr("%n local deck(s)", "", Number(match[1]))
        match = source.match(/^(\d+) rooms? available$/)
        if (match)
            return qsTr("%n room(s) available", "", Number(match[1]))
        match = source.match(/^Line (\d+) was ignored: (.+)$/)
        if (match)
            return formatStatus(qsTr("Line %1 was ignored: %2"),
                    [match[1], match[2]])
        match = source.match(
                    /^Line (\d+) did not contain a usable card\.$/)
        if (match) {
            return qsTr("Line %1 did not contain a usable card.")
                    .arg(match[1])
        }
        match = source.match(/^Game (\d+)$/)
        if (match)
            return qsTr("Game %1").arg(match[1])
        match = source.match(/^(.+) wins Game (\d+)$/)
        if (match)
            return formatStatus(qsTr("%1 wins Game %2"),
                    [match[1], match[2]])
        match = source.match(/^(.+) wins the match$/)
        if (match)
            return qsTr("%1 wins the match").arg(match[1])
        match = source.match(/^(.+) conceded(?: · Score (\d+)–(\d+))?$/)
        if (match) {
            const detail = qsTr("%1 conceded").arg(match[1])
            return match[2]
                    ? formatStatus(qsTr("%1 · Score %2–%3"),
                    [detail, match[2], match[3]])
                    : detail
        }
        match = source.match(
                    /^(.+) left the match(?: · Score (\d+)–(\d+))?$/)
        if (match) {
            const detail = qsTr("%1 left the match").arg(match[1])
            return match[2]
                    ? formatStatus(qsTr("%1 · Score %2–%3"),
                    [detail, match[2], match[3]])
                    : detail
        }
        match = source.match(/^Caching (.+)…$/)
        if (match)
            return qsTr("Caching %1…").arg(match[1])
        match = source.match(/^Downloading (.+)…$/)
        if (match)
            return qsTr("Downloading %1…").arg(match[1])
        match = source.match(
                    /^Catalog ready · (\d+) cards · (\d+) Chinese printings$/)
        if (match) {
            return formatStatus(qsTr("Catalog ready · %1 cards · %2 Chinese printings"),
                    [match[1], match[2]])
        }
        match = source.match(
                    /^Could not cache (.+): (Scryfall Chinese metadata|Scryfall English metadata|MTGCH metadata|card image|card data) via ([^:]+): (.+)$/)
        if (match) {
            return formatStatus(qsTr("Could not cache %1: %2 via %3: %4"),
                    [match[1], cachePhaseLabel(match[2]), match[3], cacheReasonLabel(match[4])])
        }
        match = source.match(/^Could not cache (.+)\.$/)
        if (match)
            return qsTr("Could not cache %1.").arg(match[1])
        match = source.match(
                    /^Scryfall returned an invalid (.+) bulk package descriptor \((.+)\)\.$/)
        if (match) {
            return qsTr(
                        "Scryfall returned an invalid %1 bulk package descriptor (%2).")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(
                    /^The damaged deck library was preserved as (.+)\.$/)
        if (match) {
            return qsTr("The damaged deck library was preserved as %1.")
                    .arg(match[1])
        }
        match = source.match(/^(.+) won the opening roll\.$/)
        if (match)
            return qsTr("%1 won the opening roll.").arg(match[1])
        match = source.match(/^Commander opening roll: (.+)\.$/)
        if (match)
            return qsTr("Commander opening roll: %1.").arg(match[1])
        match = source.match(/^Commander tie-break roll: (.+)\.$/)
        if (match)
            return qsTr("Commander tie-break roll: %1.").arg(match[1])
        match = source.match(/^Commander turn order: (.+)\.$/)
        if (match)
            return qsTr("Commander turn order: %1.").arg(match[1])
        match = source.match(
                    /^(.+) drew an opening hand of (\d+) cards\.$/)
        if (match) {
            return formatStatus(qsTr("%1 drew an opening hand of %2 cards."),
                    [match[1], match[2]])
        }
        match = source.match(/^(.+) drew a card\.$/)
        if (match)
            return qsTr("%1 drew a card.").arg(match[1])
        match = source.match(/^(.+) drew (\d+) cards\.$/)
        if (match)
            return formatStatus(qsTr("%1 drew %2 cards."),
                    [match[1], match[2]])
        match = source.match(/^(.+) shuffled their library\.$/)
        if (match)
            return qsTr("%1 shuffled their library.").arg(match[1])
        match = source.match(/^(.+) left the match\. (.+) wins\.$/)
        if (match) {
            return formatStatus(qsTr("%1 left the match. %2 wins."),
                    [match[1], match[2]])
        }
        match = source.match(/^(.+) left the game and was eliminated\.$/)
        if (match)
            return qsTr("%1 left the game and was eliminated.").arg(match[1])
        match = source.match(/^(.+) conceded\. (.+) wins Game (\d+)\.$/)
        if (match)
            return formatStatus(qsTr("%1 conceded. %2 wins Game %3."),
                                [match[1], match[2], match[3]])
        match = source.match(/^(.+) conceded and was eliminated\.$/)
        if (match)
            return qsTr("%1 conceded and was eliminated.").arg(match[1])
        match = source.match(/^(.+) wins the Commander game\.$/)
        if (match)
            return qsTr("%1 wins the Commander game.").arg(match[1])
        match = source.match(/^(.+) goes first after losing Game (\d+)\.$/)
        if (match)
            return formatStatus(qsTr("%1 goes first after losing Game %2."),
                                [match[1], match[2]])
        match = source.match(
                    /^(.+) is searching (their|.+\'s) library\.$/)
        if (match) {
            return formatStatus(qsTr("%1 is searching %2 library."),
                    [match[1], libraryOwnerLabel(match[2])])
        }
        match = source.match(
                    /^(.+) looked at the top (\d+) card\(s\) of (their|.+\'s) library\.$/)
        if (match) {
            return formatStatus(qsTr("%1 looked at the top %2 card(s) of %3 library."),
                    [match[1], match[2], libraryOwnerLabel(match[3])])
        }
        match = source.match(/^(.+) attached a permanent\.$/)
        if (match)
            return qsTr("%1 attached a permanent.").arg(match[1])
        match = source.match(/^(.+) detached a permanent\.$/)
        if (match)
            return qsTr("%1 detached a permanent.").arg(match[1])
        match = source.match(
                    /^(.+) took mulligan (\d+) and drew (\d+) cards\.$/)
        if (match) {
            return formatStatus(qsTr("%1 took mulligan %2 and drew %3 cards."),
                    [match[1], match[2], match[3]])
        }
        match = source.match(
                    /^(.+) revealed (\d+) card\(s\) from hand\.$/)
        if (match) {
            return formatStatus(qsTr("%1 revealed %2 card(s) from hand."),
                    [match[1], match[2]])
        }
        match = source.match(
                    /^(.+) searched (their|.+\'s) library and put (.+?) (face down onto .+|into .+|onto .+|on top of .+|on bottom of .+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 searched %2 library and put %3 %4."),
                    [match[1], libraryOwnerLabel(match[2]), libraryCardDescriptionLabel(match[3], resolveCardName), searchDestinationLabel(match[4])])
        }
        match = source.match(
                    /^(.+) resolved the top (\d+) card\(s\) of (their|.+\'s) library and put (\d+) card\(s\) (face down onto .+|onto .+|into .+|on top of .+|on bottom of .+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 resolved the top %2 card(s) of %3 library and put %4 card(s) %5."),
                    [match[1], match[2], libraryOwnerLabel(match[3]), match[4], searchDestinationLabel(match[5])])
        }
        match = source.match(
                    /^(.+) resolved the top (\d+) card\(s\) of (their|.+\'s) library across (\d+) destination\(s\)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 resolved the top %2 card(s) of %3 library across %4 destination(s)."),
                    [match[1], match[2], libraryOwnerLabel(match[3]), match[4]])
        }
        match = source.match(
                    /^(.+) resolved the top (\d+) card\(s\) of (their|.+\'s) library\.$/)
        if (match) {
            return formatStatus(qsTr("%1 resolved the top %2 card(s) of %3 library."),
                    [match[1], match[2], libraryOwnerLabel(match[3])])
        }
        match = source.match(
                    /^(.+) moved (.+) from (hand|battlefield|graveyard|exile|stack|reveal|library|command|sideboard|.+\'s (?:graveyard|exile)) to (hand|battlefield|graveyard|exile|stack|reveal|library|command|sideboard|library \((?:top|bottom), in (?:random )?order\)|library and shuffled the library|.+\'s battlefield)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 moved %2 from %3 to %4."),
                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), libraryTargetLabel(match[3]), moveDestinationLabel(match[4])])
        }
        match = source.match(/^(.+) removed (\d+) token\(s\) from the battlefield\.$/)
        if (match) {
            return formatStatus(qsTr("%1 removed %2 token(s) from the battlefield."),
                                [match[1], match[2]])
        }
        match = source.match(/^(.+) set (.+) on (.+) to (\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set %2 on %3 to %4."),
                    [match[1], match[2] === "number" ? qsTr("number") : match[2],
                     libraryCardDescriptionLabel(match[3], resolveCardName), match[4]])
        }
        match = source.match(
                    /^(.+) set life to (-?\d+) \(([+-]\d+)\)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set life to %2 (%3)."),
                    [match[1], match[2], match[3]])
        }
        match = source.match(
                    /^(.+) set (.+) to (-?\d+) \(([+-]\d+)\)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set %2 to %3 (%4)."),
                    [match[1], playerCounterLabel(match[2]), match[3], match[4]])
        }
        match = source.match(/^(.+) renamed counter (.+) to (.+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 renamed counter %2 to %3."),
                    [match[1], playerCounterLabel(match[2]), match[3]])
        }
        match = source.match(/^(.+) advanced to the (.+) step\.$/)
        if (match) {
            return formatStatus(qsTr("%1 advanced to the %2 step."),
                    [match[1], gamePhaseLabel(match[2])])
        }
        match = source.match(/^(.+) began their turn\.$/)
        if (match)
            return qsTr("%1 began their turn.").arg(match[1])
        match = source.match(
                    /^(.+) recorded (.+) as land play (\d+) this turn\.$/)
        if (match) {
            return formatStatus(qsTr("%1 recorded %2 as land play %3 this turn."),
                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), match[3]])
        }
        match = source.match(
                    /^(.+) set recorded land plays this turn to (\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set recorded land plays this turn to %2."),
                    [match[1], match[2]])
        }
        match = source.match(
                    /^(.+) declared (\d+) attacker\(s\) toward (.+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 declared %2 attacker(s) toward %3."),
                    [match[1], match[2], match[3]])
        }
        match = source.match(/^(.+) declared (\d+) blocker\(s\)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 declared %2 blocker(s)."),
                    [match[1], match[2]])
        }
        match = source.match(
                    /^(.+) cast (.+) from the command zone; the next additional cost is \+(\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 cast %2 from the command zone; the next additional cost is +%3."),
                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), match[3]])
        }
        match = source.match(
                    /^(.+) set (.+) command-zone cast count to (\d+); additional cost is \+(\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set %2 command-zone cast count to %3; additional cost is +%4."),
                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), match[3], match[4]])
        }
        match = source.match(
                    /^(.+) recorded (\d+) combat damage from (.+) to (.+); commander damage is now (\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 recorded %2 combat damage from %3 to %4; commander damage is now %5."),
                    [match[1], match[2], libraryCardDescriptionLabel(match[3], resolveCardName), match[4], match[5]])
        }
        match = source.match(
                    /^(.+) set commander damage from (.+) to (.+) to (\d+)\.$/)
        if (match) {
            return formatStatus(qsTr("%1 set commander damage from %2 to %3 to %4."),
                    [match[1], libraryCardDescriptionLabel(match[2], resolveCardName), match[3], match[4]])
        }
        match = source.match(/^(.+) has no response\.$/)
        if (match)
            return qsTr("%1 has no response.").arg(match[1])
        match = source.match(/^(.+) asked the table to wait\.$/)
        if (match)
            return qsTr("%1 asked the table to wait.").arg(match[1])
        return protocolError(source)
    }

    function gamePhaseLabel(phase) {
        const phaseNames = {
            "untap": "Untap", "upkeep": "Upkeep", "draw": "Draw",
            "main1": "Main 1", "begin_combat": "Begin combat",
            "declare_attackers": "Attackers", "declare_blockers": "Blockers",
            "combat_damage": "Damage", "end_combat": "End combat",
            "main2": "Main 2", "end": "End"
        }
        if (Object.prototype.hasOwnProperty.call(phaseNames, phase))
            return tr(phaseNames[phase])
        if (phase === "cleanup")
            return qsTranslate("RulesTable", "Cleanup")
        switch (phase) {
        case "Untap":
        case "Upkeep":
        case "Draw":
        case "Main 1":
        case "Begin combat":
        case "Attackers":
        case "Blockers":
        case "Damage":
        case "End combat":
        case "Main 2":
        case "End":
            return tr(phase)
        default:
            return phase
        }
    }

    function cachePhaseLabel(phase) {
        switch (phase) {
        case "Scryfall Chinese metadata":
            return qsTr("Scryfall Chinese metadata")
        case "Scryfall English metadata":
            return qsTr("Scryfall English metadata")
        case "MTGCH metadata":
            return qsTr("MTGCH metadata")
        case "card image":
            return qsTr("card image")
        case "card data":
            return qsTr("card data")
        default:
            return phase
        }
    }

    function cacheReasonLabel(reason) {
        switch (reason) {
        case "invalid JSON response":
            return qsTr("invalid JSON response")
        case "invalid image data":
            return qsTr("invalid image data")
        case "provider is temporarily unavailable":
            return qsTr("provider is temporarily unavailable")
        case "could not write the image cache":
            return qsTr("could not write the image cache")
        default:
            return reason
        }
    }

    function searchDestinationLabel(destination) {
        let match = destination.match(/^face down onto (.+)$/)
        if (match)
            return qsTr("face down onto %1").arg(libraryTargetLabel(match[1]))
        match = destination.match(/^into (.+)$/)
        if (match)
            return qsTr("into %1").arg(libraryTargetLabel(match[1]))
        match = destination.match(/^onto (.+)$/)
        if (match)
            return qsTr("onto %1").arg(libraryTargetLabel(match[1]))
        match = destination.match(/^on top of (.+)$/)
        if (match)
            return qsTr("on top of %1").arg(libraryTargetLabel(match[1]))
        match = destination.match(/^on bottom of (.+)$/)
        if (match)
            return qsTr("on bottom of %1").arg(libraryTargetLabel(match[1]))
        return destination
    }

    function libraryOwnerLabel(owner) {
        if (owner === "their")
            return qsTr("their")
        if (owner.endsWith("'s"))
            return qsTr("%1's").arg(owner.slice(0, -2))
        return owner
    }

    function libraryTargetLabel(target) {
        if (target === "their library")
            return qsTr("their library")
        const ownedZone = target.match(
                              /^(.+)\'s (hand|battlefield|graveyard|exile)$/)
        if (ownedZone) {
            return formatStatus(qsTr("%1's %2"),
                    [ownedZone[1], zoneLabel(ownedZone[2])])
        }
        return zoneLabel(target)
    }

    function playerCounterLabel(label) {
        const match = label.match(/^counter-([1-7])$/)
        return match ? qsTr("counter-%1").arg(match[1]) : label
    }

    function libraryCardDescriptionLabel(description, resolveCardName) {
        if (description === "a card")
            return qsTr("a card")
        if (description === "a face-down card")
            return qsTr("a face-down card")
        const countMatch = description.match(/^(\d+) card\(s\)$/)
        if (countMatch)
            return qsTr("%n card(s)", "", Number(countMatch[1]))
        return typeof resolveCardName === "function"
                ? resolveCardName(description) || description : description
    }

    function moveDestinationLabel(destination) {
        switch (destination) {
        case "library (top, in order)": return qsTr("library top, in order")
        case "library (bottom, in order)": return qsTr("library bottom, in order")
        case "library (top, in random order)": return qsTr("library top, in random order")
        case "library (bottom, in random order)": return qsTr("library bottom, in random order")
        case "library and shuffled the library": return qsTr("library, then shuffled it")
        }
        const battlefieldSuffix = "'s battlefield"
        if (destination.endsWith(battlefieldSuffix)) {
            const translatedBattlefield = zoneLabel("battlefield")
            if (translatedBattlefield === "battlefield")
                return destination
            const player = destination.slice(
                             0, destination.length - battlefieldSuffix.length)
            return player + " · " + translatedBattlefield
        }
        return zoneLabel(destination)
    }

    function zoneLabel(zone) {
        switch (zone) {
        case "hand":
            return qsTr("hand")
        case "battlefield":
            return qsTr("battlefield")
        case "graveyard":
            return qsTr("graveyard")
        case "exile":
            return qsTr("exile")
        case "stack":
            return qsTr("stack")
        case "reveal":
            return qsTr("reveal")
        case "library":
            return qsTr("library")
        case "command": {
            const translated = qsTranslate("BattlefieldView", "Command")
            return translated === "Command" ? zone : translated
        }
        case "sideboard": {
            const translated = qsTranslate("SideboardPanel", "Sideboard")
            return translated === "Sideboard" ? zone : translated
        }
        default:
            return zone
        }
    }

    function protocolError(source) {
        const separator = source.indexOf(":")
        const code = separator >= 0 ? source.slice(0, separator) : source
        const messages = {
            "wrong_password": qsTr("Incorrect password"),
            "room_full": qsTr("The room is full"),
            "room_not_found": qsTr("Room not found"),
            "spectators_not_allowed": qsTr("Spectators are not allowed"),
            "spectator_limit": qsTr("The spectator limit has been reached"),
            "already_in_room": qsTr("Leave the current room first"),
            "not_host": qsTr("Only the host can do that"),
            "not_in_room": qsTr("You are not in a room"),
            "invalid_message": qsTr("The server could not process the request"),
            "name_required": qsTr("A display name is required"),
            "unsupported_format": qsTr("Unsupported format"),
            "invalid_target": qsTr("Invalid target"),
            "cannot_kick_host": qsTr("The host cannot be removed"),
            "invalid_match_mode": qsTr("Invalid match mode"),
            "invalid_card_load_mode": qsTr("Invalid card image loading mode"),
            "invalid_rules_mode": qsTr("Invalid gameplay rules mode"),
            "player_host_lost": qsTr("The host engine was lost. This game was aborted without a winner. Prepare hosting and ready up to start a new game."),
            "player_host_trust_required": qsTr("This is a player-hosted Forge room. Confirm that you trust the host before joining."),
            "rules_unavailable": qsTr("Forge rules are unavailable on this server"),
            "rules_action_rejected": qsTr("The Forge decision is stale or no longer available"),
            "not_player": qsTr("Only players can do that"),
            "invalid_deck": qsTr("This deck cannot be used in the room"),
            "deck_required": qsTr("Select a playable deck first"),
            "seats_not_filled": qsTr("All seats must be filled first"),
            "not_loading": qsTr("No card loading task is active"),
            "stale_load": qsTr("The card loading task has expired"),
            "match_started": qsTr("The match has already started"),
            "game_not_started": qsTr("The game has not started"),
            "game_finished": qsTr("The game has finished"),
            "match_not_finished": qsTr("The match has not finished"),
            "library_empty": qsTr("The library is empty"),
            "game_setup_failed": qsTr("The game zones could not be created"),
            "invalid_zone": qsTr("Invalid card zone"),
            "card_not_found": qsTr("The card was not found in its source zone"),
            "invalid_position": qsTr("Invalid battlefield position"),
            "invalid_move": qsTr("The card could not be moved"),
            "invalid_phase": qsTr("Invalid phase"),
            "not_active_player": qsTr("Only the active player can do that"),
            "invalid_counter": qsTr("Invalid counter operation"),
            "invalid_chat": qsTr("Invalid chat message"),
            "invalid_token": qsTr("Invalid token data"),
            "player_eliminated": qsTr("You have been eliminated"),
            "not_sideboarding": qsTr("Sideboarding is not active"),
            "invalid_sideboard_move": qsTr("Invalid sideboard move"),
            "sideboard_not_expired": qsTr("The sideboard timer has not expired"),
            "server_limit": qsTr("The server is at capacity"),
            "rate_limited": qsTr("Too many actions; try again shortly"),
            "replay_not_found": qsTr("The replay was not found or has expired"),
            "permission_denied": qsTr("The library request was declined"),
            "approval_required": qsTr("This action requires approval"),
            "approval_pending": qsTr("An approval request is already pending"),
            "approval_expired": qsTr("The approval has expired"),
            "timeout": qsTr("Connection timed out"),
            "socket": qsTr("Network connection error"),
            "parse": qsTr("Invalid server message"),
            "protocol": qsTr("Incompatible protocol")
        }
        return messages[code] ? messages[code] : source
    }
}
