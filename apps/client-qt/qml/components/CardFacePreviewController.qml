// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

pragma ComponentBehavior: Bound
import QtQuick
import "TokenPresentation.js" as TokenPresentation

QtObject {
    id: root
    property var catalogModel: null
    property var card: ({})
    property var sourceItem: null
    property bool identityVisible: true
    property bool tokenArt: false
    property bool active: true
    property bool prioritizeImages: true
    property string fallbackImageSource: ""
    property int selectedFaceIndex: -1
    property bool previewInitialized: false
    property var prioritizedFaceKeys: ({})

    readonly property bool hasIdentity: identityVisible && !!card && !!card.name
        && card.faceDown !== true && card.visibleIdentity !== false && card.visible !== false
    readonly property string identityKey: hasIdentity
        ? [card.id || card.cardId || card.instanceId || "", card.name, card.faceName || "",
           card.setCode || "", card.collectorNumber || ""].join("\u001f") : ""
    readonly property var faces: {
        if (!active || !hasIdentity || !catalogModel || typeof catalogModel.cardFaces !== "function") return []
        void catalogModel.imageRevision
        void catalogModel.language
        return catalogModel.cardFaces(card.name, card.setCode || "", card.collectorNumber || "") || []
    }
    readonly property bool canSwitch: hasIdentity && faces.length > 1
    readonly property int initialFaceIndex: {
        const name = String(card && (card.faceName || card.name) || "").trim().toLowerCase()
        for (let index = 0; index < faces.length; ++index) {
            const face = faces[index]
            if (String(face.faceName || face.name || "").trim().toLowerCase() === name)
                return index
        }
        return 0
    }
    readonly property int faceIndex: selectedFaceIndex >= 0 && selectedFaceIndex < faces.length
        ? selectedFaceIndex : initialFaceIndex
    readonly property var viewedCard: hasIdentity ? cardForFace(faceIndex) : ({})
    readonly property string viewedName: hasIdentity
        ? String(viewedCard.faceName || viewedCard.name || "") : ""
    readonly property string displayName: active && hasIdentity ? nameForCard(viewedCard) : ""
    readonly property string imageSource: active && hasIdentity ? imageForCard(viewedCard, faceIndex) : ""
    readonly property string fallbackText: active && hasIdentity ? textForCard(viewedCard) : ""
    readonly property var displayFaces: {
        if (!active || !hasIdentity) return []
        const indices = [initialFaceIndex]
        for (let index = 0; index < faces.length; ++index)
            if (index !== initialFaceIndex) indices.push(index)
        return indices.map(index => {
            const faceCard = cardForFace(index)
            return {faceIndex: index, card: faceCard,
                    name: String(faceCard.faceName || faceCard.name || ""),
                    displayName: nameForCard(faceCard),
                    imageSource: imageForCard(faceCard, index), fallbackText: textForCard(faceCard)}
        })
    }

    onIdentityKeyChanged: {
        resetFace()
        prioritizedFaceKeys = ({})
        schedulePreparation()
    }
    onActiveChanged: if (active) schedulePreparation()
    onCatalogModelChanged: {
        resetFace()
        prioritizedFaceKeys = ({})
        schedulePreparation()
    }
    onSourceItemChanged: resetFace()
    onFacesChanged: if (selectedFaceIndex >= faces.length) resetFace()
    onDisplayFacesChanged: if (previewInitialized) Qt.callLater(root.prioritizeFaces)
    onPrioritizeImagesChanged: if (prioritizeImages && previewInitialized) Qt.callLater(root.prioritizeFaces)
    Component.onCompleted: {
        previewInitialized = true
        preparePreview()
    }

    function resetFace() { selectedFaceIndex = -1 }
    function cardForFace(index) {
        if (!hasIdentity) return ({})
        if (faces.length === 0) return card
        // Catalog records own each face's printing, including meld results.
        // Only the authoritative current face may retain source face text.
        const source = index === initialFaceIndex ? card
            : Object.assign({}, card, {displayName: "", typeLine: "", oracleText: "",
                                      rulesText: "", manaCost: "", power: "", toughness: ""})
        return Object.assign({}, source, faces[index])
    }
    function nameForCard(faceCard) {
        if (catalogModel) {
            void catalogModel.language
            void catalogModel.imageRevision
        }
        const name = String(faceCard.faceName || faceCard.name || "")
        if (tokenArt) return TokenPresentation.details(catalogModel, faceCard).displayName
        if (catalogModel && typeof catalogModel.cardDisplayName === "function")
            return catalogModel.cardDisplayName(name) || faceCard.displayName || name
        return faceCard.displayName || name
    }
    function imageForCard(faceCard, index) {
        if (catalogModel) {
            void catalogModel.imageRevision
            void catalogModel.language
            const name = String(faceCard.faceName || faceCard.name || "")
            let source = ""
            if (typeof catalogModel.previewImageSource === "function")
                source = catalogModel.previewImageSource(name, faceCard.setCode || "", faceCard.collectorNumber || "", tokenArt)
            else if (tokenArt && typeof catalogModel.tokenImageSource === "function")
                source = catalogModel.tokenImageSource(name, faceCard.setCode || "", faceCard.collectorNumber || "")
            else if (!tokenArt && typeof catalogModel.imageSource === "function")
                source = catalogModel.imageSource(name, faceCard.setCode || "", faceCard.collectorNumber || "")
            if (source) return source
        }
        // An unavailable other face must never display the current face's art.
        return index === initialFaceIndex ? fallbackImageSource : ""
    }
    function textForCard(faceCard) {
        if (tokenArt) return TokenPresentation.fullText(TokenPresentation.details(catalogModel, faceCard))
        let rules = ""
        if (catalogModel && typeof catalogModel.cardRulesText === "function") {
            void catalogModel.imageRevision
            void catalogModel.language
            rules = catalogModel.cardRulesText(String(faceCard.faceName || faceCard.name || ""),
                faceCard.setCode || "", faceCard.collectorNumber || "") || ""
        }
        if (!rules) rules = faceCard.oracleText || faceCard.rulesText || ""
        return [nameForCard(faceCard), faceCard.typeLine || "", rules].filter(part => part).join("\n\n")
    }
    function schedulePreparation() {
        if (previewInitialized) Qt.callLater(root.preparePreview)
    }
    function preparePreview() {
        if (!previewInitialized || !active || !hasIdentity || !catalogModel) return
        // Only explicit, visible inspection may hydrate legacy face metadata.
        // Passive face enumeration remains local and never initiates a fetch.
        if (typeof catalogModel.prepareCardFacePreview === "function")
            catalogModel.prepareCardFacePreview(card.name, card.setCode || "", card.collectorNumber || "")
        prioritizeFaces()
    }
    function prioritizeFaces() {
        if (!previewInitialized || !active || !hasIdentity || !prioritizeImages || !catalogModel) return
        for (const face of displayFaces) {
            const value = face.card
            const key = [value.name, value.faceName || "", value.setCode || "", value.collectorNumber || "",
                         tokenArt ? "token" : "card", catalogModel.language || ""].join("\u001f")
            if (prioritizedFaceKeys[key]) continue
            prioritizedFaceKeys[key] = true
            if (tokenArt) TokenPresentation.prioritize(catalogModel, value)
            else if (typeof catalogModel.prioritizeCards === "function") catalogModel.prioritizeCards([value])
            else if (typeof catalogModel.cacheCards === "function") catalogModel.cacheCards([value])
        }
    }
    function nextFace() {
        if (!active || !canSwitch) return
        selectedFaceIndex = (faceIndex + 1) % faces.length
        prioritizeFaces()
    }
}
