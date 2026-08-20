// SPDX-License-Identifier: GPL-2.0-only
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
        default:
            return format
        }
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
            return category
        }
    }

    function status(source) {
        if (!source)
            return source
        const exact = tr(source)
        if (exact !== source)
            return exact
        return patternedStatus(source)
    }

    function patternedStatus(source) {
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
        let match = source.match(/^(.+) is missing from the local card database\.$/)
        if (match)
            return qsTr("%1 is missing from the local card database.").arg(match[1])
        match = source.match(/^(.+) is not legal in (.+)\.$/)
        if (match)
            return qsTr("%1 is not legal in %2.").arg(match[1]).arg(match[2])
        match = source.match(/^(.+) is restricted to one copy in Vintage\.$/)
        if (match)
            return qsTr("%1 is restricted to one copy in Vintage.").arg(match[1])
        match = source.match(/^(.+) has (\d+) copies; commander formats are singleton\.$/)
        if (match) {
            return qsTr("%1 has %2 copies; commander formats are singleton.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(/^(.+) has (\d+) copies; this format allows at most four\.$/)
        if (match) {
            return qsTr("%1 has %2 copies; this format allows at most four.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(/^(.+) is outside the commanders' color identity\.$/)
        if (match)
            return qsTr("%1 is outside the commanders' color identity.").arg(match[1])
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
                return qsTr("At least four checked-in players are required.")
            case "tournament_round_incomplete":
                return qsTr("Confirm every table result before advancing the round.")
            case "tournament_result_invalid":
                return qsTr("That match result is not valid for this pairing.")
            }
        }
        match = source.match(/^(\d+) main · (\d+) side(?: · (.+))?$/)
        if (match) {
            return qsTr("%1 main · %2 side").arg(match[1]).arg(match[2])
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
            return qsTr("%1 of %2 seats filled").arg(match[1]).arg(match[2])
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
            return qsTr("Line %1 was ignored: %2").arg(match[1]).arg(match[2])
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
            return qsTr("%1 wins Game %2").arg(match[1]).arg(match[2])
        match = source.match(/^(.+) wins the match$/)
        if (match)
            return qsTr("%1 wins the match").arg(match[1])
        match = source.match(/^(.+) conceded(?: · Score (\d+)–(\d+))?$/)
        if (match) {
            const detail = qsTr("%1 conceded").arg(match[1])
            return match[2]
                    ? qsTr("%1 · Score %2–%3")
                      .arg(detail).arg(match[2]).arg(match[3])
                    : detail
        }
        match = source.match(
                    /^(.+) left the match(?: · Score (\d+)–(\d+))?$/)
        if (match) {
            const detail = qsTr("%1 left the match").arg(match[1])
            return match[2]
                    ? qsTr("%1 · Score %2–%3")
                      .arg(detail).arg(match[2]).arg(match[3])
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
            return qsTr("Catalog ready · %1 cards · %2 Chinese printings")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(
                    /^Could not cache (.+): (Scryfall Chinese metadata|Scryfall English metadata|MTGCH metadata|card image|card data) via ([^:]+): (.+)$/)
        if (match) {
            return qsTr("Could not cache %1: %2 via %3: %4")
                    .arg(match[1])
                    .arg(cachePhaseLabel(match[2]))
                    .arg(match[3])
                    .arg(cacheReasonLabel(match[4]))
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
        match = source.match(
                    /^(.+) drew an opening hand of (\d+) cards\.$/)
        if (match) {
            return qsTr("%1 drew an opening hand of %2 cards.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(/^(.+) drew a card\.$/)
        if (match)
            return qsTr("%1 drew a card.").arg(match[1])
        match = source.match(/^(.+) drew (\d+) cards\.$/)
        if (match)
            return qsTr("%1 drew %2 cards.").arg(match[1]).arg(match[2])
        match = source.match(/^(.+) shuffled their library\.$/)
        if (match)
            return qsTr("%1 shuffled their library.").arg(match[1])
        match = source.match(/^(.+) left the match\. (.+) wins\.$/)
        if (match) {
            return qsTr("%1 left the match. %2 wins.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(/^(.+) left the game and was eliminated\.$/)
        if (match)
            return qsTr("%1 left the game and was eliminated.").arg(match[1])
        match = source.match(
                    /^(.+) is searching (their|.+\'s) library\.$/)
        if (match) {
            return qsTr("%1 is searching %2 library.")
                    .arg(match[1]).arg(libraryOwnerLabel(match[2]))
        }
        match = source.match(
                    /^(.+) looked at the top (\d+) card\(s\) of (their|.+\'s) library\.$/)
        if (match) {
            return qsTr("%1 looked at the top %2 card(s) of %3 library.")
                    .arg(match[1]).arg(match[2])
                    .arg(libraryOwnerLabel(match[3]))
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
            return qsTr("%1 took mulligan %2 and drew %3 cards.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(
                    /^(.+) revealed (\d+) card\(s\) from hand\.$/)
        if (match) {
            return qsTr("%1 revealed %2 card(s) from hand.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(
                    /^(.+) searched (their|.+\'s) library and put (.+?) (face down onto .+|into .+|onto .+|on top of .+|on bottom of .+)\.$/)
        if (match) {
            return qsTr("%1 searched %2 library and put %3 %4.")
                    .arg(match[1])
                    .arg(libraryOwnerLabel(match[2]))
                    .arg(libraryCardDescriptionLabel(match[3]))
                    .arg(searchDestinationLabel(match[4]))
        }
        match = source.match(
                    /^(.+) resolved the top (\d+) card\(s\) of (their|.+\'s) library and put (\d+) card\(s\) (face down onto .+|onto .+|into .+|on top of .+|on bottom of .+)\.$/)
        if (match) {
            return qsTr("%1 resolved the top %2 card(s) of %3 library and put %4 card(s) %5.")
                    .arg(match[1]).arg(match[2])
                    .arg(libraryOwnerLabel(match[3])).arg(match[4])
                    .arg(searchDestinationLabel(match[5]))
        }
        match = source.match(
                    /^(.+) resolved the top (\d+) card\(s\) of (their|.+\'s) library\.$/)
        if (match) {
            return qsTr("%1 resolved the top %2 card(s) of %3 library.")
                    .arg(match[1]).arg(match[2])
                    .arg(libraryOwnerLabel(match[3]))
        }
        match = source.match(
                    /^(.+) moved (.+) from (hand|battlefield|graveyard|exile|stack|reveal|library|command|sideboard|.+\'s (?:graveyard|exile)) to (hand|battlefield|graveyard|exile|stack|reveal|library|command|sideboard|.+\'s battlefield)\.$/)
        if (match) {
            return qsTr("%1 moved %2 from %3 to %4.")
                    .arg(match[1]).arg(libraryCardDescriptionLabel(match[2]))
                    .arg(libraryTargetLabel(match[3]))
                    .arg(moveDestinationLabel(match[4]))
        }
        match = source.match(/^(.+) set (.+) on (.+) to (\d+)\.$/)
        if (match) {
            return qsTr("%1 set %2 on %3 to %4.")
                    .arg(match[1]).arg(match[2])
                    .arg(match[3]).arg(match[4])
        }
        match = source.match(
                    /^(.+) set life to (-?\d+) \(([+-]\d+)\)\.$/)
        if (match) {
            return qsTr("%1 set life to %2 (%3).")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(
                    /^(.+) set (.+) to (-?\d+) \(([+-]\d+)\)\.$/)
        if (match) {
            return qsTr("%1 set %2 to %3 (%4).")
                    .arg(match[1]).arg(match[2])
                    .arg(match[3]).arg(match[4])
        }
        match = source.match(/^(.+) renamed counter (.+) to (.+)\.$/)
        if (match) {
            return qsTr("%1 renamed counter %2 to %3.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(/^(.+) advanced to the (.+) step\.$/)
        if (match) {
            return qsTr("%1 advanced to the %2 step.")
                    .arg(match[1]).arg(gamePhaseLabel(match[2]))
        }
        match = source.match(/^(.+) began their turn\.$/)
        if (match)
            return qsTr("%1 began their turn.").arg(match[1])
        match = source.match(
                    /^(.+) recorded (.+) as land play (\d+) this turn\.$/)
        if (match) {
            return qsTr("%1 recorded %2 as land play %3 this turn.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(
                    /^(.+) set recorded land plays this turn to (\d+)\.$/)
        if (match) {
            return qsTr("%1 set recorded land plays this turn to %2.")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(
                    /^(.+) declared (\d+) attacker\(s\) toward (.+)\.$/)
        if (match) {
            return qsTr("%1 declared %2 attacker(s) toward %3.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(/^(.+) declared (\d+) blocker\(s\)\.$/)
        if (match) {
            return qsTr("%1 declared %2 blocker(s).")
                    .arg(match[1]).arg(match[2])
        }
        match = source.match(
                    /^(.+) cast (.+) from the command zone; the next additional cost is \+(\d+)\.$/)
        if (match) {
            return qsTr("%1 cast %2 from the command zone; the next additional cost is +%3.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
        }
        match = source.match(
                    /^(.+) set (.+) command-zone cast count to (\d+); additional cost is \+(\d+)\.$/)
        if (match) {
            return qsTr("%1 set %2 command-zone cast count to %3; additional cost is +%4.")
                    .arg(match[1]).arg(match[2])
                    .arg(match[3]).arg(match[4])
        }
        match = source.match(
                    /^(.+) recorded (\d+) combat damage from (.+) to (.+); commander damage is now (\d+)\.$/)
        if (match) {
            return qsTr("%1 recorded %2 combat damage from %3 to %4; commander damage is now %5.")
                    .arg(match[1]).arg(match[2]).arg(match[3])
                    .arg(match[4]).arg(match[5])
        }
        match = source.match(
                    /^(.+) set commander damage from (.+) to (.+) to (\d+)\.$/)
        if (match) {
            return qsTr("%1 set commander damage from %2 to %3 to %4.")
                    .arg(match[1]).arg(match[2])
                    .arg(match[3]).arg(match[4])
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
            return qsTr("%1's %2").arg(ownedZone[1])
                    .arg(zoneLabel(ownedZone[2]))
        }
        return zoneLabel(target)
    }

    function libraryCardDescriptionLabel(description) {
        if (description === "a card")
            return qsTr("a card")
        const countMatch = description.match(/^(\d+) card\(s\)$/)
        if (countMatch)
            return qsTr("%n card(s)", "", Number(countMatch[1]))
        return description
    }

    function moveDestinationLabel(destination) {
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
