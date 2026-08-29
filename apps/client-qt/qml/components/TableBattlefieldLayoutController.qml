// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var tableRoot
    property var resolvedTypeLineCache: ({})

    function catalogTypeLine(cardName, card) {
        const catalog = tableRoot.cardCatalogModel
        if (!catalog || typeof catalog.cardTypeLine !== "function"
                || !cardName) {
            return ""
        }
        const key = String(cardName).toLowerCase()
                    + "\u001f"
                    + String(card.setCode ? card.setCode : "").toUpperCase()
                    + "\u001f"
                    + String(card.collectorNumber
                             ? card.collectorNumber : "")
        if (Object.prototype.hasOwnProperty.call(
                    resolvedTypeLineCache, key)) {
            return resolvedTypeLineCache[key]
        }
        const typeLine = catalog.cardTypeLine(
                           cardName,
                           card.setCode ? card.setCode : "",
                           card.collectorNumber ? card.collectorNumber : "")
        resolvedTypeLineCache[key] = typeLine
        return typeLine
    }

    function resolvedTypeLine(card) {
        if (!card || card.faceDown === true)
            return ""
        const supplied = String(card.typeLine ? card.typeLine : "").trim()
        if (card.faceName && tableRoot.presentation) {
            const faces = tableRoot.presentation.availableCardFaces(card)
            let selectedFaceIndex = -1
            for (let index = 0; index < faces.length; ++index) {
                const face = faces[index]
                const selectionName = face.faceName ? face.faceName
                                                    : (face.name ? face.name : "")
                if (selectionName !== card.faceName)
                    continue
                selectedFaceIndex = index
                if (face.typeLine)
                    return String(face.typeLine)
                break
            }
            const suppliedFaces = supplied.split(" // ")
            if (selectedFaceIndex >= 0
                    && suppliedFaces.length === faces.length
                    && suppliedFaces[selectedFaceIndex].trim().length > 0) {
                return suppliedFaces[selectedFaceIndex].trim()
            }
            const catalogFaceType = catalogTypeLine(card.faceName, card)
            if (catalogFaceType)
                return catalogFaceType
        }
        if (supplied.length > 0)
            return supplied
        return catalogTypeLine(card.name ? card.name : "", card)
    }

    function battlefieldCategory(card) {
        let typeLine = resolvedTypeLine(card).toLocaleLowerCase()
        const faceSeparator = typeLine.indexOf(" // ")
        if (faceSeparator >= 0)
            typeLine = typeLine.substring(0, faceSeparator)
        const subtypeSeparators = ["—", "–", "～", "〜"]
        for (let index = 0; index < subtypeSeparators.length; ++index) {
            const separator = typeLine.indexOf(subtypeSeparators[index])
            if (separator >= 0) {
                typeLine = typeLine.substring(0, separator)
                break
            }
        }
        if (typeLine.includes("land") || typeLine.includes("地"))
            return "land"
        if (typeLine.includes("creature") || typeLine.includes("生物"))
            return "creature"
        if (typeLine.includes("instant") || typeLine.includes("sorcery")
                || typeLine.includes("瞬间") || typeLine.includes("法术")) {
            return "spell"
        }
        if (typeLine.includes("planeswalker")
                || typeLine.includes("鹏洛客")
                || typeLine.includes("旅法师")
                || typeLine.includes("battle")
                || typeLine.includes("战役")) {
            return "planeswalker"
        }
        if (typeLine.includes("artifact") || typeLine.includes("神器"))
            return "artifact"
        // Enchantments, unknown types, and face-down permanents share the
        // neutral support cluster. Keeping hidden cards here avoids revealing
        // their real category through position.
        return "support"
    }

    function categoryOrder(category) {
        if (category === "support")
            return 0
        if (category === "artifact")
            return 1
        if (category === "planeswalker")
            return 2
        if (category === "spell")
            return 3
        if (category === "creature")
            return 4
        return 5
    }

    function battlefieldColumns(seatIndex) {
        const size = tableRoot.battlefieldScene.battlefieldSize(seatIndex)
        const gap = Theme.size(10)
        if (!size || size.width <= 0)
            return 10
        return Math.max(
                    1, Math.floor(
                        (size.width + gap)
                        / (tableRoot.battlefieldCardWidth + gap)))
    }

    function battlefieldSlot(seatIndex, category, index) {
        const columns = battlefieldColumns(seatIndex)
        const usesSupportCluster = category === "support"
                                || category === "artifact"
                                || category === "planeswalker"
        const clusterColumns = usesSupportCluster
                             ? Math.max(1, Math.floor(columns / 3))
                             : columns
        const sequenceColumn = index % clusterColumns
        let clusterStart = 0
        if (category === "artifact")
            clusterStart = Math.floor((columns - clusterColumns) / 2)
        else if (category === "planeswalker")
            clusterStart = columns - clusterColumns
        const centerColumn = Math.floor((clusterColumns - 1) / 2)
        const centerDistance = Math.ceil(sequenceColumn / 2)
        const centerOutColumn = sequenceColumn === 0
                              ? centerColumn
                              : (sequenceColumn % 2 === 1
                                 ? centerColumn + centerDistance
                                 : centerColumn - centerDistance)
        let column = clusterStart + sequenceColumn
        if (category === "creature" || category === "spell"
                || category === "artifact") {
            column = clusterStart + centerOutColumn
        } else if (category === "planeswalker") {
            column = clusterStart + clusterColumns - 1 - sequenceColumn
        }
        const row = Math.floor(index / clusterColumns)
        const size = tableRoot.battlefieldScene.battlefieldSize(seatIndex)
        let x = columns === 1 ? 0.5 : column / (columns - 1)
        if (size && size.width > tableRoot.battlefieldCardWidth) {
            const gap = Theme.size(10)
            const step = (tableRoot.battlefieldCardWidth + gap)
                         / (size.width - tableRoot.battlefieldCardWidth)
            x = column * step
        }
        const compactSupportLayout = columns < 3 && usesSupportCluster
        let y = 0.05 + row * 0.08
        if (compactSupportLayout && category === "artifact")
            y = 0.16 + row * 0.08
        else if (compactSupportLayout && category === "planeswalker")
            y = 0.27 + row * 0.08
        else if (category === "spell")
            y = (columns < 3 ? 0.40 : 0.31) + row * 0.10
        else if (category === "creature")
            y = 0.58 + row * 0.10
        else if (category === "land")
            y = 1 - row * 0.10
        return {
            "x": Math.max(0, Math.min(1, x)),
            "y": Math.max(0, Math.min(1, y))
        }
    }

    function battlefieldCardId(card) {
        if (!card)
            return ""
        return String(card.id ? card.id
                              : (card.cardId ? card.cardId : ""))
    }

    function battlefieldCardHasCounters(card) {
        return card && card.counters && card.counters.length > 0
    }

    function battlefieldCardHasRelation(card) {
        const cardId = battlefieldCardId(card)
        if (!cardId)
            return false
        const attachments = tableRoot.tableAttachments
                            ? tableRoot.tableAttachments : []
        for (let index = 0; index < attachments.length; ++index) {
            const attachment = attachments[index]
            if (attachment.sourceCardId === cardId
                    || attachment.targetCardId === cardId) {
                return true
            }
        }
        const arrows = tableRoot.tableArrows ? tableRoot.tableArrows : []
        for (let index = 0; index < arrows.length; ++index) {
            const arrow = arrows[index]
            if (arrow.sourceCardId === cardId
                    || arrow.targetCardId === cardId) {
                return true
            }
        }
        return false
    }

    function battlefieldCardCanStack(card, category, seatIndex) {
        if (!card || (category !== "land" && category !== "creature")
                || card.faceDown === true || card.commander === true
                || battlefieldCardHasCounters(card)
                || battlefieldCardHasRelation(card)) {
            return false
        }
        const ownerSeat = card.ownerSeat !== undefined
                        ? Number(card.ownerSeat) : seatIndex
        return ownerSeat < 0 || ownerSeat === seatIndex
    }

    function battlefieldCardNeedsPriority(card, seatIndex) {
        if (!card)
            return false
        const ownerSeat = card.ownerSeat !== undefined
                        ? Number(card.ownerSeat) : seatIndex
        return card.commander === true
                || battlefieldCardHasCounters(card)
                || battlefieldCardHasRelation(card)
                || (ownerSeat >= 0 && ownerSeat !== seatIndex)
    }

    function battlefieldStackKey(card, category, seatIndex) {
        if (!card)
            return ""
        const cardId = battlefieldCardId(card)
        if (!battlefieldCardCanStack(card, category, seatIndex))
            return "single\u001f" + cardId
        const name = String(card.name ? card.name : "")
                     .trim().toLocaleLowerCase()
        if (!name)
            return "unknown\u001f" + cardId
        return category + "\u001f" + name
                + "\u001f" + String(card.faceName ? card.faceName : "")
                  .trim().toLocaleLowerCase()
                + "\u001f" + (card.tapped === true ? "tapped" : "untapped")
                + "\u001f" + (card.token === true ? "token" : "card")
    }

    function battlefieldCardPosition(card) {
        if (card && card.position
                && card.position.x !== undefined
                && card.position.y !== undefined) {
            return {"x": card.position.x, "y": card.position.y}
        }
        if (card && card.x !== undefined && card.y !== undefined)
            return {"x": card.x, "y": card.y}
        return ({})
    }

    function stackedBattlefieldPosition(seatIndex, category, base,
                                        stackIndex) {
        const size = tableRoot.battlefieldScene.battlefieldSize(seatIndex)
        const availableWidth = Math.max(
                                   1, size.width
                                      - tableRoot.battlefieldCardWidth)
        const availableHeight = Math.max(
                                    1, size.height
                                       - tableRoot.battlefieldCardHeight)
        const xStep = Math.min(0.04, Theme.size(18) / availableWidth)
        const yStep = Math.min(0.025, Theme.size(7) / availableHeight)
        const xDirection = base.x > 0.72 ? -1 : 1
        const yDirection = category === "land" ? -1 : 1
        return {
            "x": Math.max(0, Math.min(
                              1, base.x
                                 + xDirection * xStep * stackIndex)),
            "y": Math.max(0, Math.min(
                              1, base.y
                                 + yDirection * yStep * stackIndex))
        }
    }

    function smartBattlefieldPosition(seatIndex, card, movingCardId) {
        const category = battlefieldCategory(card)
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          seatIndex, "battlefield")
        const pending = tableRoot.zoneState.pendingBattlefieldMovesForSeat(
                            seatIndex)
        const stackKey = battlefieldStackKey(card, category, seatIndex)
        const categoryStacks = ({})
        let stackBase = ({})
        let stackCount = 0
        const occupiedCards = cards.concat(pending)
        for (let index = 0; index < occupiedCards.length; ++index) {
            const occupied = occupiedCards[index]
            const occupiedId = occupied.id ? occupied.id : occupied.cardId
            if (occupiedId === movingCardId)
                continue
            const occupiedCategory = battlefieldCategory(occupied)
            if (occupiedCategory !== category)
                continue
            const occupiedStackKey = battlefieldStackKey(
                                         occupied, occupiedCategory,
                                         seatIndex)
            categoryStacks[occupiedStackKey] = true
            if (occupiedStackKey !== stackKey)
                continue
            const position = battlefieldCardPosition(occupied)
            if (stackCount === 0 && position.x !== undefined)
                stackBase = position
            ++stackCount
        }
        if (stackCount > 0 && stackBase.x !== undefined) {
            return stackedBattlefieldPosition(
                        seatIndex, category, stackBase, stackCount)
        }
        const categoryCount = Object.keys(categoryStacks).length
        return nonOverlappingBattlefieldPosition(
                    seatIndex,
                    battlefieldSlot(seatIndex, category, categoryCount),
                    movingCardId)
    }

    function smartBattlefieldAnchor(seatIndex, cards) {
        const values = cards ? cards : []
        const card = values.length > 0 ? values[0] : ({})
        return smartBattlefieldPosition(
                    seatIndex, card, card.id ? card.id : "")
    }

    function arrangeOwnBattlefield() {
        if (!tableRoot.canAct || tableRoot.roomSession.seatIndex < 0)
            return false
        const seatIndex = tableRoot.roomSession.seatIndex
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          seatIndex, "battlefield").slice()
        if (cards.length === 0)
            return false
        cards.sort(function(left, right) {
            const leftCategory = battlefieldCategory(left)
            const rightCategory = battlefieldCategory(right)
            const categoryDifference = categoryOrder(leftCategory)
                                       - categoryOrder(rightCategory)
            if (categoryDifference !== 0)
                return categoryDifference
            // Face-down cards stay in the neutral band, but their hidden names
            // must not influence the public ordering within that band.
            const leftName = left.faceDown === true
                           ? "" : String(left.name ? left.name : "")
            const rightName = right.faceDown === true
                            ? "" : String(right.name ? right.name : "")
            const nameDifference = leftName.localeCompare(rightName)
            if (nameDifference !== 0)
                return nameDifference
            return String(left.id).localeCompare(String(right.id))
        })
        const categoryCounts = ({
            "support": 0,
            "artifact": 0,
            "planeswalker": 0,
            "spell": 0,
            "creature": 0,
            "land": 0
        })
        const stackStates = ({})
        const placements = []
        const sameLaneAttachments = []
        const placedById = ({})
        for (let index = 0; index < cards.length; ++index) {
            const card = cards[index]
            const targetId = sameLaneAttachmentTarget(card, seatIndex)
            if (targetId) {
                sameLaneAttachments.push({
                    "card": card,
                    "targetId": targetId
                })
                continue
            }
            if (crossLaneAttachmentSource(card, seatIndex))
                continue
            const category = battlefieldCategory(card)
            const stackKey = battlefieldStackKey(
                                 card, category, seatIndex)
            let position
            if (Object.prototype.hasOwnProperty.call(stackStates, stackKey)) {
                const stackState = stackStates[stackKey]
                position = stackedBattlefieldPosition(
                               seatIndex, category, stackState.base,
                               stackState.count)
                ++stackState.count
            } else {
                position = battlefieldSlot(
                               seatIndex, category,
                               categoryCounts[category])
                ++categoryCounts[category]
                stackStates[stackKey] = {
                    "base": position,
                    "count": 1
                }
            }
            placements.push({
                "cardId": card.id,
                "position": position
            })
            placedById[card.id] = position
        }
        const stackIndexByTarget = ({})
        for (let index = 0; index < sameLaneAttachments.length; ++index) {
            const attached = sameLaneAttachments[index]
            const host = placedById[attached.targetId]
            if (!host)
                continue
            const stackIndex = stackIndexByTarget[attached.targetId] || 0
            stackIndexByTarget[attached.targetId] = stackIndex + 1
            placements.push({
                "cardId": attached.card.id,
                "position": tableRoot.attachmentUi
                            ? tableRoot.attachmentUi.attachmentStackPosition(
                                  host, stackIndex)
                            : host
            })
        }
        tableRoot.wsModel.arrangeBattlefield(placements)
        tableRoot.selection.clear()
        return true
    }

    function sameLaneAttachmentTarget(card, seatIndex) {
        if (!card || !card.id)
            return ""
        const attachment = tableRoot.gameTableModel.attachmentForSource(card.id)
        if (!attachment || !attachment.targetCardId)
            return ""
        const targetSeat = tableRoot.gameTableModel.visibleZoneSeat(
                             attachment.targetCardId, "battlefield")
        return targetSeat === seatIndex ? attachment.targetCardId : ""
    }

    function crossLaneAttachmentSource(card, seatIndex) {
        if (!card || !card.id)
            return false
        const attachment = tableRoot.gameTableModel.attachmentForSource(card.id)
        if (!attachment || !attachment.targetCardId)
            return false
        const targetSeat = tableRoot.gameTableModel.visibleZoneSeat(
                             attachment.targetCardId, "battlefield")
        return targetSeat >= 0 && targetSeat !== seatIndex
    }

    function nonOverlappingBattlefieldPosition(seatIndex, requested,
                                               movingCardId) {
        const cards = tableRoot.zoneState.zoneCardsForSeat(
                          seatIndex, "battlefield")
        const pendingCards = tableRoot.zoneState
                            .pendingBattlefieldMovesForSeat(seatIndex)
        const offsets = [
            [0, 0], [0.055, 0], [-0.055, 0], [0, 0.07],
            [0, -0.07], [0.055, 0.07], [-0.055, 0.07],
            [0.11, 0], [-0.11, 0], [0.11, 0.07], [-0.11, 0.07]
        ]
        for (let offsetIndex = 0; offsetIndex < offsets.length;
             ++offsetIndex) {
            const candidate = {
                "x": Math.max(0, Math.min(
                                  1, requested.x + offsets[offsetIndex][0])),
                "y": Math.max(0, Math.min(
                                  1, requested.y + offsets[offsetIndex][1]))
            }
            let overlaps = false
            for (let cardIndex = 0; cardIndex < cards.length; ++cardIndex) {
                const card = cards[cardIndex]
                if (card.id === movingCardId || !card.position)
                    continue
                if (Math.abs(card.position.x - candidate.x) < 0.04
                    && Math.abs(card.position.y - candidate.y) < 0.055) {
                    overlaps = true
                    break
                }
            }
            if (!overlaps) {
                for (let cardIndex = 0;
                     cardIndex < pendingCards.length; ++cardIndex) {
                    const card = pendingCards[cardIndex]
                    if (card.id === movingCardId)
                        continue
                    if (Math.abs(card.x - candidate.x) < 0.04
                        && Math.abs(card.y - candidate.y) < 0.055) {
                        overlaps = true
                        break
                    }
                }
            }
            if (!overlaps)
                return candidate
        }
        const occupiedCount = cards.length + pendingCards.length
        return {
            "x": Math.max(0, Math.min(
                              1, requested.x + 0.04
                                 * ((occupiedCount % 5) + 1))),
            "y": Math.max(0, Math.min(
                              1, requested.y + 0.06
                                 * ((occupiedCount % 3) + 1)))
        }
    }

    function batchBattlefieldPosition(anchor, index, count) {
        const columns = Math.ceil(Math.sqrt(count))
        const rows = Math.ceil(count / columns)
        const column = index % columns
        const row = Math.floor(index / columns)
        const xSpacing = columns > 1
                         ? Math.min(0.09, 0.9 / (columns - 1)) : 0.09
        const ySpacing = rows > 1
                         ? Math.min(0.09, 0.9 / (rows - 1)) : 0.09
        const xRadius = (columns - 1) * xSpacing / 2
        const yRadius = (rows - 1) * ySpacing / 2
        const centerX = Math.max(xRadius,
                                 Math.min(1 - xRadius, anchor.x))
        const centerY = Math.max(yRadius,
                                 Math.min(1 - yRadius, anchor.y))
        return {
            "x": Math.max(0, Math.min(
                              1, centerX
                                 + (column - (columns - 1) / 2) * xSpacing)),
            "y": Math.max(0, Math.min(
                              1, centerY
                                 + (row - (rows - 1) / 2) * ySpacing))
        }
    }
}
