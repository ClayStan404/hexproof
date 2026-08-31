// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <QObject>

class TestDeckLibrary : public QObject
{
    Q_OBJECT

  private slots:
    void parsesMoxfieldAndPlainSections() const;
    void benchmarkCommanderDeckParsing() const;
    void benchmarkEmptyLibraryStartup() const;
    void importsPersistsAndBuildsCubeProduct() const;
    void keepsIncompleteCubeEditableButUnplayable() const;
    void migratesLegacyCubesIntoDeckLibrary() const;
    void formatsExplicitDeckSideboardAndCommanderSections() const;
    void roundTripsFormattedDeckTextThroughTheParser() const;
    void persistsConsiderWithoutRegisteringItForMatches() const;
    void exportsDeckTextAndSavesUtf8File() const;
    void loadsDeckTextFromUtf8File() const;
    void rejectsInvalidDeckListFiles() const;
    void rejectsNonLocalDeckExportUrl() const;
    void failedDeckExportLeavesExistingTarget() const;
    void replacesExistingDeckExportFile() const;
    void parsesMoxfieldPrintingDecorations() const;
    void parsesMultipleCommanders() const;
    void parsesSplitCardNames() const;
    void parsesBlankLineSideboard() const;
    void parsesBlankLineCommander() const;
    void rejectsOversizedImports() const;
    void rejectsInvalidAndOverflowingCounts() const;
    void appliesLargerCubeImportLimits() const;
    void rejectsControlCharacters() const;
    void allowsInteractiveBasicLandCopies() const;
    void importsFiltersEditsAndPersists() const;
    void validatesOnlyAffectedDecks() const;
    void legalityWarningsDoNotBlockDeckSelection() const;
    void edhReadinessRequiresCommanderAndImages() const;
    void duelCommanderImportsFiltersAndBuildsPayload() const;
    void changesDeckFormatWithoutLosingCards() const;
    void changesDeckToCubeWithoutLosingCards() const;
    void coalescesCardMetadataPersistence() const;
    void backgroundMetadataSaveCannotOverwriteSynchronousEdit() const;
    void retriesFailedBackgroundMetadataSave() const;
    void keepsMetadataDirtyAfterBoundedBackgroundRetries() const;
    void designatesUpToTwoCommanders() const;
    void readinessRequiresAnOpeningHand() const;
    void preservesCorruptLibraryBeforeWriting() const;
    void preservesMalformedLibrarySchema() const;
    void migratesLegacyTableFormatsToDeckFormats() const;
    void preservesCorruptPreferencesBeforeWriting() const;
    void keepsDamagedPreferencesWhenRenameFails() const;
    void storesUiAndCardLanguagesSeparately() const;
    void storesCardArtProviderPreference() const;
    void storesLocalArtReusePreference() const;
    void storesPackOpeningAnimationPreference() const;
    void storesAndClampsInterfaceScale() const;
    void storesTableLayoutPreferences() const;
    void storesCustomShortcutPreferences() const;
    void rejectsShortcutConflictsAndInvalidSequences() const;
    void reportsEditorFailuresThroughLastError() const;
    void buildsPrivateMatchDeckPayload() const;
    void categorizesLocalizedTypeLines() const;
    void keepsDistinctPrintingCacheRequests() const;
    void doesNotCacheArtOnImportUntilRequested() const;
    void hydratesTypeLineFromCatalogWithoutCachingArt() const;
    void appliesDoubleFacedPrintingUnderFaceName() const;
    void reportsImportWarnings() const;
    void storesDeckTokensAndActivatesThemForMatches() const;
    void backfillsLegacyDeckTokenMetadata() const;
};
