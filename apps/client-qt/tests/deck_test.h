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
    void benchmarkLargeCubeParsing() const;
    void benchmarkLargeCubeProjection() const;
    void sharesCardProjectionsAndInvalidatesEditedInputs() const;
    void editsNotifyOnlyTheAffectedLibraryRow() const;
    void structuralSaveDoesNotPublishUnrelatedMetadata() const;
    void refreshesLibraryDisplayPathsWithoutBlocking() const;
    void refreshesImageCountsAndKeepsMatchChecksLive() const;
    void benchmarkEmptyLibraryStartup() const;
    void importsPersistsAndBuildsCubeProduct() const;
    void keepsIncompleteCubeEditableButUnplayable() const;
    void migratesLegacyCubesIntoDeckLibrary() const;
    void formatsExplicitDeckSideboardAndCommanderSections() const;
    void formatsPublishedTournamentDecklists() const;
    void roundTripsFormattedDeckTextThroughTheParser() const;
    void persistsConsiderWithoutRegisteringItForMatches() const;
    void exportsDeckTextAndSavesUtf8File() const;
    void snapshotsArtExportRequestsForOnlyTheSelectedDeck() const;
    void loadsDeckTextFromUtf8File() const;
    void rejectsInvalidDeckListFiles() const;
    void rejectsNonLocalDeckExportUrl() const;
    void failedDeckExportLeavesExistingTarget() const;
    void replacesExistingDeckExportFile() const;
    void parsesMoxfieldPrintingDecorations() const;
    void preservesSpecialCollectorNumbers() const;
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
    void rejectsValidationFromPreviousDeckFormat() const;
    void legalityWarningsDoNotBlockDeckSelection() const;
    void edhReadinessRequiresCommanderAndImages() const;
    void duelCommanderImportsFiltersAndBuildsPayload() const;
    void changesDeckFormatWithoutLosingCards() const;
    void changesDeckToCubeWithoutLosingCards() const;
    void targetsExactPrintingForCountsMovesAndPrintingChanges() const;
    void mergesCountsWhenChangingToExistingPrinting() const;
    void keepsDistinctPrintingsAcrossAddAndConsiderMoves() const;
    void keepsNameOnlyRowsNameKeyedAndDfcAliasesEditable() const;
    void appliesMetadataOnlyToMatchingCardLocations() const;
    void limitsDisplayPathResolutionToChangedCards() const;
    void invalidatesDisplayPathsOnlyForArtOrPrintingMetadata() const;
    void recoversDownloadedArtAtAnUnchangedSavedPath() const;
    void refreshesDisplayPathsAndMetadataAfterPrintingMerge() const;
    void defersInitialDisplayPathsInBoundedBatches_data() const;
    void defersInitialDisplayPathsInBoundedBatches() const;
    void deferredDisplayPathsFollowCurrentEditedRows() const;
    void cancelsDeferredDisplayPathsWhenResolverChanges() const;
    void refreshesOnlyChangedCustomArtPrintingsWithoutHydrationOrSaving() const;
    void refreshesCardWideCustomArtInPrioritizedBoundedBatches() const;
    void mergesCustomArtRefreshWithPendingStartupAndEdits() const;
    void customArtRestorePreservesOfficialReadinessAndCancelsSafely() const;
    void customArtRefreshResolvesSeparateMeldAliases() const;
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
    void ignoresRemovedThemePreferences() const;
    void storesUiThemePreference() const;
    void storesTableBackgroundIndependentlyOfTheme() const;
    void rejectsUnknownTableBackgrounds() const;
    void rollsBackTableBackgroundWhenSavingFails() const;
    void storesSponsorAnnouncementAcknowledgement() const;
    void storesCardArtRepairNoticeAcknowledgement() const;
    void storesAndClampsInterfaceScale() const;
    void storesTableLayoutPreferences() const;
    void storesCustomShortcutPreferences() const;
    void rejectsShortcutConflictsAndInvalidSequences() const;
    void reportsEditorFailuresThroughLastError() const;
    void buildsPrivateMatchDeckPayload() const;
    void categorizesLocalizedTypeLines() const;
    void keepsDistinctPrintingCacheRequests() const;
    void recachesExistingDeckEntriesToExpandFaces() const;
    void doesNotCacheArtOnImportUntilRequested() const;
    void hydratesTypeLineFromCatalogWithoutCachingArt() const;
    void resolvesCatalogPrintingsBeforeDeckRegistration() const;
    void ignoresStaleCatalogPrintingsAfterAnEdit() const;
    void mergesResolvedPrintingsAndRefreshesCardLocations() const;
    void appliesDoubleFacedPrintingUnderFaceName() const;
    void reportsImportWarnings() const;
    void storesDeckTokensAndActivatesThemForMatches() const;
    void backfillsLegacyDeckTokenMetadata() const;
    void persistsEmblemKindsAndIncludesSupportArtRequests() const;
    void infersLegacySupportKindsFromLayoutAndType() const;
};
