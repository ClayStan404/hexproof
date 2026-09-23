# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

cmake_minimum_required(VERSION 3.21)

set(HEXPROOF_VERSION "2.1.0")
set(HEXPROOF_VERSION_OVERRIDE "" CACHE STRING "Hexproof release version override")
if(HEXPROOF_VERSION_OVERRIDE)
    set(HEXPROOF_VERSION "${HEXPROOF_VERSION_OVERRIDE}")
endif()
project(hexproof VERSION "${HEXPROOF_VERSION}" LANGUAGES CXX)

if(POLICY CMP0207)
    cmake_policy(SET CMP0207 NEW)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

option(HEXPROOF_ENABLE_SANITIZERS
    "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
if(HEXPROOF_ENABLE_SANITIZERS)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        message(FATAL_ERROR
            "HEXPROOF_ENABLE_SANITIZERS requires GCC or Clang")
    endif()
    add_compile_options(
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
        -fno-sanitize-recover=all)
    add_link_options(
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
        -fno-sanitize-recover=all)
endif()

# Off by default so a new compiler or platform warning cannot break a release
# build. Linux CI enables it against a verified warning-free tree.
option(HEXPROOF_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
option(HEXPROOF_BUILD_NATIVE_AUDIT
    "Build the opt-in native GUI automation executable (never installed)" OFF)

set(HEXPROOF_SERVER_DIRECTORY_FILE "" CACHE FILEPATH
    "JSON server directory embedded in the client")
if(HEXPROOF_SERVER_DIRECTORY_FILE)
    get_filename_component(HEXPROOF_SERVER_DIRECTORY_RESOURCE
        "${HEXPROOF_SERVER_DIRECTORY_FILE}" ABSOLUTE
        BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/config/servers.json")
    set(HEXPROOF_SERVER_DIRECTORY_RESOURCE
        "${CMAKE_CURRENT_SOURCE_DIR}/config/servers.json")
else()
    set(HEXPROOF_SERVER_DIRECTORY_RESOURCE
        "${CMAKE_CURRENT_SOURCE_DIR}/config/servers.example.json")
endif()
if(NOT EXISTS "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
    message(FATAL_ERROR
        "Hexproof server directory not found: ${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
endif()
set_source_files_properties("${HEXPROOF_SERVER_DIRECTORY_RESOURCE}"
    PROPERTIES QT_RESOURCE_ALIAS "config/servers.json")
message(STATUS
    "Hexproof client server directory: ${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")

if(MSVC)
    add_compile_options(/W4)
    if(HEXPROOF_WARNINGS_AS_ERRORS)
        add_compile_options(/WX)
    endif()
else()
    add_compile_options(-Wall -Wextra -Wpedantic)
    if(HEXPROOF_WARNINGS_AS_ERRORS)
        add_compile_options(-Werror)
    endif()
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Concurrent
    Core
    Gui
    LinguistTools
    Multimedia
    Network
    Quick
    QuickEffects
    QuickTest
    ShaderTools
    Sql
    Test
    WebSockets)
find_package(ZLIB REQUIRED)

qt_standard_project_setup()

# Application icons are committed static assets; no build-time generation or
# Python dependency.
set(HEXPROOF_ICONS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons")
set(HEXPROOF_APP_ICON_PNG "${HEXPROOF_ICONS_DIR}/hexproof.png")
set(HEXPROOF_MACOS_ICON "${HEXPROOF_ICONS_DIR}/hexproof.icns")
set(HEXPROOF_WINDOWS_ICON "${HEXPROOF_ICONS_DIR}/hexproof.ico")
set_source_files_properties("${HEXPROOF_APP_ICON_PNG}" PROPERTIES
    QT_RESOURCE_ALIAS "assets/hexproof.png")

set(HEXPROOF_PLATFORM_SOURCES)
if(APPLE)
    set_source_files_properties("${HEXPROOF_MACOS_ICON}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources")
    list(APPEND HEXPROOF_PLATFORM_SOURCES "${HEXPROOF_MACOS_ICON}")
elseif(WIN32)
    file(RELATIVE_PATH HEXPROOF_WINDOWS_ICON_REL
        "${CMAKE_CURRENT_BINARY_DIR}"
        "${HEXPROOF_WINDOWS_ICON}")
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/assets/windows/hexproof.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/hexproof-icon.rc"
        @ONLY)
    list(APPEND HEXPROOF_PLATFORM_SOURCES
        "${CMAKE_CURRENT_BINARY_DIR}/hexproof-icon.rc")
endif()

set(HEXPROOF_DECK_CORE_SOURCES
    src/deck/Deck.cpp
    src/deck/DeckEditor.cpp
    src/deck/DeckFormat.cpp
    src/deck/DeckListFileIO.cpp
    src/deck/DeckParser.cpp
)

qt_add_library(hexproof_deck_core STATIC ${HEXPROOF_DECK_CORE_SOURCES})
target_include_directories(hexproof_deck_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_deck_core PUBLIC Qt6::Core)

set(HEXPROOF_DECK_LIBRARY_SOURCES
    src/models/DeckLibraryEditing.cpp
    src/models/DeckLibraryImportExport.cpp
    src/models/DeckLibraryMetadata.cpp
    src/models/DeckLibraryModel.cpp
    src/models/DeckLibraryQueries.cpp
    src/models/DeckLibraryStorage.cpp
    src/models/DeckLibraryValidation.cpp
    src/models/ShortcutRegistry.cpp
)

qt_add_library(hexproof_deck_library STATIC
    ${HEXPROOF_DECK_LIBRARY_SOURCES})
target_include_directories(hexproof_deck_library PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_deck_library PUBLIC
    hexproof_deck_core
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui)

set(HEXPROOF_SESSION_SOURCES
    src/services/HubTransport.cpp
    src/services/GameSessionState.cpp
    src/services/LimitedSessionState.cpp
    src/services/LimitedDeckDraftStore.cpp
    src/services/ProtocolSession.cpp
    src/services/ReconnectController.cpp
    src/services/RoomSessionState.cpp
    src/services/RulesChoiceModel.cpp
    src/services/RulesCombatModel.cpp
    src/services/RulesDamageModel.cpp
    src/services/RulesOrderModel.cpp
    src/services/RulesSessionState.cpp
    src/services/ForgeReplayService.cpp
    src/services/RulesStateModels.cpp
    src/services/ServerDirectory.cpp
    src/services/TournamentSessionState.cpp
    src/services/PeerTransportService.cpp
    src/services/WsClientPeer.cpp
    src/services/ForgeHostDiagnostics.cpp
    src/services/ForgeHostService.cpp
    src/services/ModelOpponentService.cpp
    src/services/WsClient.cpp
    src/services/WsClientCommands.cpp
    src/services/WsClientTournamentCommands.cpp
    src/services/WsClientDispatch.cpp
    src/services/WsMessageParser.cpp
)

qt_add_library(hexproof_session STATIC ${HEXPROOF_SESSION_SOURCES})
target_include_directories(hexproof_session PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_session PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}")
target_link_libraries(hexproof_session PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::WebSockets
    ZLIB::ZLIB)

qt_add_library(hexproof_local_test STATIC src/testing/LocalTestSession.cpp)
target_link_libraries(hexproof_local_test PUBLIC hexproof_session)

set(HEXPROOF_TABLE_MODEL_SOURCES
    src/models/GameTableModel.cpp
    src/models/OptimisticCommandModel.cpp
    src/models/SideboardTableModel.cpp
    src/models/ZoneCardModel.cpp
)

qt_add_library(hexproof_table_models STATIC ${HEXPROOF_TABLE_MODEL_SOURCES})
target_include_directories(hexproof_table_models PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_table_models PUBLIC Qt6::Core)

set(HEXPROOF_CARD_SERVICE_SOURCES
    src/services/CardServiceLog.cpp
    src/services/CardArtAudit.cpp
    src/services/CardArtArchive.cpp
    src/services/CardArtDeckExport.cpp
    src/services/CardArtCache.cpp
    src/services/CardArtManager.cpp
    src/services/CardArtStorage.cpp
    src/services/CustomCardArtStore.cpp
    src/services/CustomCardArtFiles.cpp
    src/services/CustomCardArtTransfer.cpp
    src/services/CardCatalog.cpp
    src/services/CardCatalogCustomArt.cpp
    src/services/CardCatalogFaceExpansion.cpp
    src/services/CardCatalogImportFacade.cpp
    src/services/CatalogImport.cpp
    src/services/CatalogBulkImport.cpp
    src/services/CatalogReleaseManifest.cpp
    src/services/CardCatalogSearch.cpp
    src/services/CardCatalogSearchPreview.cpp
    src/services/CardCatalogPrintings.cpp
    src/services/CardCatalogLookup.cpp
    src/services/CardCatalogLimited.cpp
    src/services/CardCatalogLimitedArt.cpp
    src/services/CardCatalogCache.cpp
    src/services/CardCatalogMatch.cpp
    src/services/CardCatalogResolveQueue.cpp
    src/services/CardCatalogResolveCompletion.cpp
    src/services/CardCatalogInstallerOfficial.cpp
    src/services/CardCatalogInstallerBulk.cpp
    src/services/CardCatalogRelease.cpp
    src/services/CardImageProvider.cpp
    src/services/DeckLegalityService.cpp
    src/services/CardResolver.cpp
    src/services/CardResolverQueue.cpp
    src/services/CardResolverRequests.cpp
    src/services/CardResolverReplies.cpp
    src/services/CardResolverPolicy.cpp
    src/services/CardResolverCompletion.cpp
    src/services/CatalogInstaller.cpp
    src/services/CatalogInstallerOfficial.cpp
    src/services/CatalogRepository.cpp
    src/services/CatalogRepositorySearch.cpp
    src/services/CatalogRepositoryCards.cpp
    src/services/CatalogRepositoryLookup.cpp
    src/services/CatalogRepositoryLocalized.cpp
    src/services/CatalogRepositoryLimited.cpp
    src/services/CatalogStorage.cpp
    src/services/NetworkRequestFactory.cpp
)

qt_add_library(hexproof_card_services STATIC ${HEXPROOF_CARD_SERVICE_SOURCES})
target_include_directories(hexproof_card_services PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_card_services PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}")
target_link_libraries(hexproof_card_services PUBLIC
    hexproof_deck_core
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Quick
    Qt6::Sql
    ZLIB::ZLIB)

qt_add_library(hexproof_update_service STATIC
    src/services/AppUpdateService.cpp
)
target_include_directories(hexproof_update_service PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_update_service PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}")
target_link_libraries(hexproof_update_service PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Network)

qt_add_library(hexproof_content_service STATIC
    src/services/PublicContentSchema.cpp
    src/services/PublicContentService.cpp
    src/services/PublicContentPresentation.cpp)
target_include_directories(hexproof_content_service PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_content_service PUBLIC Qt6::Core Qt6::Gui Qt6::Network)
qt_add_resources(hexproof_content_service "content_defaults"
    PREFIX "/"
    FILES
        config/content/sponsors.json
        config/content/announcements.json
        assets/sponsors/a1100011.jpg
        assets/sponsors/afdian-1a326.png
        assets/sponsors/anjisuan.jpg
        assets/sponsors/dodo.jpg
        assets/sponsors/m0nta9e.jpg
        assets/sponsors/orangezihan.jpeg
        assets/sponsors/guafu.jpeg
        assets/sponsors/beidi.jpeg
        assets/sponsors/qingbao.jpg)

set(HEXPROOF_APPLICATION_SOURCES
    src/main.cpp
    src/models/ClientPreferencesModel.cpp
    src/services/AudioController.cpp
    src/services/BackgroundMusicController.cpp
    src/services/MatchCardCacheBinding.cpp
    src/services/MatchLoadCoordinator.cpp
    src/services/TranslationController.cpp
)
qt_add_executable(hexproof ${HEXPROOF_PLATFORM_SOURCES} ${HEXPROOF_APPLICATION_SOURCES})

target_include_directories(hexproof PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}")

set(HEXPROOF_APPLICATION_QML_FILES
        "${HEXPROOF_APP_ICON_PNG}"
        "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}"
        qml/Main.qml
        qml/ProfileUnavailable.qml
        qml/components/qmldir
        qml/components/ActivityRing.qml
        qml/components/AppBackground.qml
        qml/components/SoundEffects.qml
        qml/components/OperationSounds.qml
        qml/components/TableBackgrounds.qml
        qml/components/TableBackgroundPicker.qml
        qml/components/TableBackgroundPopup.qml
        qml/components/AppButton.qml
        qml/components/AppMenu.qml
        qml/components/AppMenuItem.qml
        qml/components/AppMenuSeparator.qml
        qml/components/AppPopup.qml
        qml/components/AppPopupHeader.qml
        qml/components/AppScrollBar.qml
        qml/components/GlassChrome.qml
        qml/components/LiquidGlass.qml
        qml/components/AppComboBox.qml
        qml/components/AppTextField.qml
        qml/components/AppToggle.qml
        qml/components/ApplicationUpdatePanel.qml
        qml/components/BrandMark.qml
        qml/components/BattlefieldCardDelegate.qml
        qml/components/BattlefieldSeatState.qml
        qml/components/BattlefieldOpponentPublicZonePile.qml
        qml/components/BattlefieldOpponentZoneDock.qml
        qml/components/BattlefieldView.qml
        qml/components/BattlefieldViewControls.qml
        qml/components/CardCounterEditor.qml
        qml/components/CardCacheProgress.qml
        qml/components/ScrollChainHandler.qml
        qml/components/ShortcutHints.qml
        qml/components/CardFacePicker.qml
        qml/components/CardSearchPopup.qml
        qml/components/CardFilterState.qml
        qml/components/CardFilterBar.qml
        qml/components/CardArtGrid.qml
        qml/components/CompactCardList.qml
        qml/components/CardManaCurve.qml
        qml/components/CardManaCost.qml
        qml/components/CardManaSymbol.qml
        qml/components/CardListRow.qml
        qml/components/ManaSymbols.qml
        qml/components/CardMetadataNotice.qml
        qml/components/CardHoverPreview.qml
        qml/components/TokenPresentation.js
        qml/components/CardTypes.js
        qml/components/TokenDetailsPopup.qml
        qml/components/CombatDeclarationPopup.qml
        qml/components/CommanderDamagePopup.qml
        qml/components/ConfirmDialog.qml
        qml/components/ForgeHostingDialog.qml
        qml/components/ForgeMigrationControls.qml
        qml/components/ForgePeerControls.qml
        qml/components/ConfigurableShortcut.qml
        qml/components/ConditionalMenuItem.qml
        qml/components/ConditionalMenuSeparator.qml
        qml/components/ExportDeckDialog.qml
        qml/components/DeckArtExportDialog.qml
        qml/components/CustomCardArtDialog.qml
        qml/components/DeckCardActionsMenu.qml
        qml/components/CustomArtImportDialog.qml
        qml/components/StorageLocationPanel.qml
        qml/components/CounterLabelPopup.qml
        qml/components/GameResultPopup.qml
        qml/components/HandView.qml
        qml/components/SpectatorHandView.qml
        qml/components/DeckCardRow.qml
        qml/components/DeckVisualCard.qml
        qml/components/DeckMainCollection.qml
        qml/components/DeckConsiderManager.qml
        qml/components/DeckPicker.qml
        qml/components/DeckTokenManager.qml
        qml/components/EmblemBrowser.qml
        qml/components/DiceRollPopup.qml
        qml/components/InfoBanner.qml
        qml/components/I18n.qml
        qml/components/RulesText.qml
        qml/components/RulesStartFailureNotice.qml
        qml/components/LibraryPositionPopup.qml
        qml/components/LandPlayPopup.qml
        qml/components/LibrarySearchCardList.qml
        qml/components/LibrarySearchContextMenu.qml
        qml/components/LibrarySearchInspector.qml
        qml/components/LibraryTopCardsControls.qml
        qml/components/LibraryTopCardsView.qml
        qml/components/LibrarySearchPopup.qml
        qml/components/LimitedCardGrouping.qml
        qml/components/LimitedCardGroupView.qml
        qml/components/LimitedDeckBuilder.qml
        qml/components/LimitedCommanderSelection.qml
        qml/components/CommanderDraftPlan.qml
        qml/components/CubeRoomRules.qml
        qml/components/LimitedCommanderPicker.qml
        qml/components/CommanderCubeMatches.qml
        qml/components/LimitedBasicLandPlan.qml
        qml/components/CubeRoomSeats.qml
        qml/components/CubeRoomMatches.qml
        qml/components/EventScreenRouter.qml
        qml/components/LimitedCardTile.qml
        qml/components/LimitedDraftSeatMap.qml
        qml/components/LimitedDraftView.qml
        qml/components/LimitedSetPicker.qml
        qml/components/LimitedProductArtPanel.qml
        qml/components/LimitedSideboardBasicLandsPanel.qml
        qml/components/LimitedSideboardFilters.qml
        qml/components/LifeEditorPopup.qml
        qml/components/NumberInputPopup.qml
        qml/components/PackOpeningOverlay.qml
        qml/components/PlayerCounterPip.qml
        qml/components/PrintingPicker.qml
        qml/components/RoomListQuery.qml
        qml/components/RulesBattlefieldView.qml
        qml/components/RulesBattlefieldLayout.qml
        qml/components/RulesTableInteraction.qml
        qml/components/RulesPriorityController.qml
        qml/components/RulesPriorityMode.qml
        qml/components/RulesPhaseStops.qml
        qml/components/RulesActionBar.qml
        qml/components/RulesInspectionDock.qml
        qml/components/RulesCardSelectionPrompt.qml
        qml/components/RulesCardBrowser.qml
        qml/components/RulesCardChoiceDialog.qml
        qml/components/RulesDecisionDialog.qml
        qml/components/RulesZoneActions.qml
        qml/components/RulesCardSurface.qml
        qml/components/ForgeCard.qml
        qml/components/ForgeCardLane.qml
        qml/components/ForgeHand.qml
        qml/components/ForgeManaPool.qml
        qml/components/ForgeStack.qml
        qml/components/ForgeArrow.qml
        qml/components/ForgeCombatInteraction.qml
        qml/components/ForgeDuelTable.qml
        qml/components/ForgeZonePile.qml
        qml/components/RulesLegacyLayout.qml
        qml/components/RulesCardInspector.qml
        qml/components/RulesCardPersistentState.qml
        qml/components/RulesCardHoverPreview.qml
        qml/components/RulesDecisionDock.qml
        qml/components/RulesCardActionPicker.qml
        qml/components/RulesCombatAssignmentPrompt.qml
        qml/components/RulesHorizontalListView.qml
        qml/components/RulesDamageAssignmentPrompt.qml
        qml/components/RulesDamageDialog.qml
        qml/components/RulesHandArea.qml
        qml/components/RulesMatchControls.qml
        qml/components/RulesNumberPrompt.qml
        qml/components/RulesOpponentZoneDock.qml
        qml/components/RulesOrderPrompt.qml
        qml/components/RulesScryPrompt.qml
        qml/components/RulesCardNamePrompt.qml
        qml/components/RulesPromptPanel.qml
        qml/components/RulesPromptContext.qml
        qml/components/RulesRevealPrompt.qml
        qml/components/RulesScalarChoicePrompt.qml
        qml/components/RulesStackRail.qml
        qml/components/RulesTableActionRail.qml
        qml/components/RulesTargetSelectionPrompt.qml
        qml/components/ScreenHeader.qml
        qml/components/SettingsPage.qml
        qml/components/SettingsModuleRow.qml
        qml/components/SegmentedControl.qml
        qml/components/ShortcutActionCatalog.qml
        qml/components/CardArtRepairNoticePopup.qml
        qml/components/SponsorAnnouncementPopup.qml
        qml/components/SponsorCatalog.qml
        qml/components/ContentRefreshBar.qml
        qml/components/SponsorHighlight.qml
        qml/components/SponsorList.qml
        qml/components/SponsorSupportPopup.qml
        qml/components/SharedZonesView.qml
        qml/components/SideboardPanel.qml
        qml/components/SideboardBoardReview.qml
        qml/components/SideboardPreviewLayer.qml
        qml/components/SideboardZoneView.qml
        qml/components/StatusPill.qml
        qml/components/Surface.qml
        qml/components/Theme.qml
        qml/components/TableSettingsPopup.qml
        qml/components/TableActionRail.qml
        qml/components/TableAreaMenus.qml
        qml/components/TableAttachmentController.qml
        qml/components/TableAttachmentStackLayer.qml
        qml/components/TableBattlefieldGeometry.qml
        qml/components/TableBattlefieldLayoutController.qml
        qml/components/TableBattlefieldSceneController.qml
        qml/components/TableCardMoveController.qml
        qml/components/TableCardActionController.qml
        qml/components/TableCardPresentationController.qml
        qml/components/TableCardToolsMenu.qml
        qml/components/TableDialogs.qml
        qml/components/TableEditorPopups.qml
        qml/components/TableGameLogRail.qml
        qml/components/TableGameValueController.qml
        qml/components/TableHandArea.qml
        qml/components/TableLandPlayController.qml
        qml/components/TableLibraryMenus.qml
        qml/components/TableOwnCommandZonePile.qml
        qml/components/TableOwnLibraryPile.qml
        qml/components/TableOwnPlayerStatus.qml
        qml/components/TableOwnPublicZonePile.qml
        qml/components/TableOwnZoneDock.qml
        qml/components/TableMenus.qml
        qml/components/TableOptimisticCommandController.qml
        qml/components/TableOpponentZonePanelLayer.qml
        qml/components/TableOverlayLayer.qml
        qml/components/TableProjectionSyncController.qml
        qml/components/TableRelationLayer.qml
        qml/components/TableRuntimeSyncController.qml
        qml/components/TableRulesAssistController.qml
        qml/components/TableSeatStateController.qml
        qml/components/TableSceneShell.qml
        qml/components/TableSelectionController.qml
        qml/components/TableSessionUiController.qml
        qml/components/TableGameShortcuts.qml
        qml/components/TableLibraryShortcuts.qml
        qml/components/TableSelectionShortcuts.qml
        qml/components/TableShortcutContext.qml
        qml/components/TableShortcuts.qml
        qml/components/TableShortcutHelp.qml
        qml/components/TableViewShortcuts.qml
        qml/components/TableSharedZoneController.qml
        qml/components/TableTransientStateController.qml
        qml/components/TableTurnBar.qml
        qml/components/TableZoneStateController.qml
        qml/components/TokenPicker.qml
        qml/components/TournamentDecklistPopup.qml
        qml/components/TournamentEventDesk.qml
        qml/components/TournamentScoreEditor.qml
        qml/components/ZoneBrowserPopup.qml
        assets/sponsors/alipay-pay.png
        assets/sponsors/wechat-pay.png
        qml/assets/card-back.jpg
        qml/assets/playmat-dusk.png
        qml/assets/backgrounds/forest.png
        qml/assets/backgrounds/astral.png
        qml/assets/backgrounds/volcanic.png
        qml/assets/backgrounds/frost.png
        qml/assets/backgrounds/ink.png
        qml/assets/backgrounds/woven.png
        qml/assets/mana/mana.ttf
        qml/assets/mana/OFL.txt
        qml/assets/mana/README.md
        qml/screens/MainMenu.qml
        qml/screens/Connect.qml
        qml/screens/CreateRoom.qml
        qml/screens/LimitedHub.qml
        qml/screens/LimitedRoomCreate.qml
        qml/screens/DeckEditor.qml
        qml/screens/DeckLibrary.qml
        qml/screens/ImportDeck.qml
        qml/screens/JoinRoom.qml
        qml/screens/MatchLoading.qml
        qml/screens/RoomBrowser.qml
        qml/screens/Settings.qml
        qml/screens/ModelSettings.qml
        qml/screens/AppearanceSettings.qml
        qml/screens/LanguageSettings.qml
        qml/screens/CatalogSettings.qml
        qml/screens/UpdatesSettings.qml
        qml/screens/SetArtDownload.qml
        qml/screens/CardArtManager.qml
        qml/screens/CustomCardArtManager.qml
        qml/screens/ShortcutSettings.qml
        qml/screens/AudioSettings.qml
        qml/screens/GameplaySettings.qml
        qml/screens/Sponsors.qml
        qml/screens/Announcements.qml
        qml/screens/RulesTable.qml
        qml/screens/ForgeReplay.qml
        qml/screens/ForgeReplayLibrary.qml
        qml/screens/Table.qml
        qml/screens/TournamentBrowser.qml
        qml/screens/TournamentCreate.qml
        qml/screens/TournamentLobby.qml
        qml/screens/CubeRoom.qml
        qml/components/TournamentChat.qml
        qml/components/TournamentPlayers.qml
        qml/components/TournamentSidebar.qml
        qml/components/LimitedEventProgress.qml
        qml/screens/WaitingRoom.qml)
qt_add_resources(hexproof "app_qml"
    PREFIX "/"
    FILES ${HEXPROOF_APPLICATION_QML_FILES})

set(HEXPROOF_AUDIO_FILES)
foreach(cue IN ITEMS click select draw play tap shuffle attack block cast resolve turn damage confirm cancel error)
    list(APPEND HEXPROOF_AUDIO_FILES "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/${cue}.wav")
endforeach()
qt_add_resources(hexproof "operation_audio"
    PREFIX "/audio" BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio"
    FILES ${HEXPROOF_AUDIO_FILES})
set(HEXPROOF_MUSIC_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/music/Gitana.mp3"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/music/bgm2.ogg"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/music/bgm3.ogg")
qt_add_resources(hexproof "background_music"
    PREFIX "/music" BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/music"
    FILES ${HEXPROOF_MUSIC_FILES})

qt_add_translations(hexproof
    TS_FILES i18n/hexproof_zh_CN.ts
    RESOURCE_PREFIX "/i18n"
    LUPDATE_OPTIONS -locations relative)
set(HEXPROOF_UI_QM_FILE
    "${CMAKE_CURRENT_BINARY_DIR}/hexproof_zh_CN.qm")

qt_add_lrelease(
    TS_FILES i18n/hexproof_dynamic_zh_CN.ts
    QM_FILES_OUTPUT_VARIABLE HEXPROOF_DYNAMIC_QM_FILES)
qt_add_resources(hexproof "dynamic_translations"
    PREFIX "/i18n"
    BASE "${CMAKE_CURRENT_BINARY_DIR}"
    FILES ${HEXPROOF_DYNAMIC_QM_FILES})

set(HEXPROOF_APPLICATION_LIBRARIES
    hexproof_local_test
    hexproof_card_services
    hexproof_deck_library
    hexproof_session
    hexproof_table_models
    hexproof_update_service
    hexproof_content_service
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Multimedia
    Qt6::Network
    Qt6::Quick
    Qt6::QuickEffects
    Qt6::Sql
    Qt6::WebSockets
    ZLIB::ZLIB)
target_link_libraries(hexproof PRIVATE ${HEXPROOF_APPLICATION_LIBRARIES})

qt_add_shaders(hexproof "liquidglass_shaders"
    BATCHABLE
    PRECOMPILE
    OPTIMIZED
    PREFIX "/shaders"
    FILES
        qml/shaders/liquidglass.frag)

if(HEXPROOF_BUILD_NATIVE_AUDIT)
    # Compile the production entry point and embed the same source/resource
    # lists. Never link incidental .o files from a previously built client.
    qt_add_executable(hexproof_native_audit
        ${HEXPROOF_APPLICATION_SOURCES}
        src/testing/NativeAudit.cpp
        src/testing/NativeAudit.h)
    target_include_directories(hexproof_native_audit PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(hexproof_native_audit PRIVATE
        HEXPROOF_VERSION="${PROJECT_VERSION}"
        HEXPROOF_NATIVE_AUDIT=1)
    target_link_libraries(hexproof_native_audit PRIVATE
        ${HEXPROOF_APPLICATION_LIBRARIES} Qt6::Test)
    # Exercise the real GTK chooser through widget key events when available.
    # This optional adapter is never linked into the release application.
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(NATIVE_AUDIT_GTK QUIET IMPORTED_TARGET gtk+-3.0 x11)
            if(TARGET PkgConfig::NATIVE_AUDIT_GTK)
                target_sources(hexproof_native_audit PRIVATE
                    src/testing/NativeGtkInput.cpp src/testing/NativeGtkInput.h)
                target_link_libraries(hexproof_native_audit PRIVATE PkgConfig::NATIVE_AUDIT_GTK)
                target_compile_definitions(hexproof_native_audit PRIVATE HEXPROOF_NATIVE_AUDIT_GTK=1)
            endif()
        endif()
    endif()
    qt_add_resources(hexproof_native_audit "native_app_qml"
        PREFIX "/"
        FILES ${HEXPROOF_APPLICATION_QML_FILES})
    qt_add_resources(hexproof_native_audit "native_operation_audio"
        PREFIX "/audio" BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio"
        FILES ${HEXPROOF_AUDIO_FILES})
    qt_add_resources(hexproof_native_audit "native_background_music"
        PREFIX "/music" BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/music"
        FILES ${HEXPROOF_MUSIC_FILES})
    qt_add_resources(hexproof_native_audit "native_translations"
        PREFIX "/i18n"
        BASE "${CMAKE_CURRENT_BINARY_DIR}"
        FILES "${HEXPROOF_UI_QM_FILE}" ${HEXPROOF_DYNAMIC_QM_FILES})
    qt_add_shaders(hexproof_native_audit "native_liquidglass_shaders"
        BATCHABLE PRECOMPILE OPTIMIZED PREFIX "/shaders"
        FILES qml/shaders/liquidglass.frag)
    if(TARGET Qt6::QWebpPlugin)
        qt_import_plugins(hexproof_native_audit INCLUDE Qt6::QWebpPlugin)
    endif()
endif()

if(TARGET Qt6::QWebpPlugin)
    qt_import_plugins(hexproof INCLUDE Qt6::QWebpPlugin)
else()
    get_target_property(HEXPROOF_QT_CORE_TYPE Qt6::Core TYPE)
    if(NOT HEXPROOF_QT_CORE_TYPE STREQUAL "SHARED_LIBRARY")
        message(FATAL_ERROR
            "Qt WebP image plugin is required for MTGCH card art.")
    endif()

    if(IS_ABSOLUTE "${QT6_INSTALL_PLUGINS}")
        set(HEXPROOF_QT_PLUGIN_DIR "${QT6_INSTALL_PLUGINS}")
    else()
        set(HEXPROOF_QT_PLUGIN_DIR
            "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}")
    endif()
    file(GLOB HEXPROOF_QT_WEBP_PLUGINS
        "${HEXPROOF_QT_PLUGIN_DIR}/imageformats/*qwebp*${CMAKE_SHARED_LIBRARY_SUFFIX}")
    if(NOT HEXPROOF_QT_WEBP_PLUGINS)
        message(FATAL_ERROR
            "Qt WebP image plugin is required for MTGCH card art.")
    endif()
endif()

set_target_properties(hexproof PROPERTIES
    WIN32_EXECUTABLE ON
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_BUNDLE_NAME "Hexproof"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.claystan404.hexproof"
    MACOSX_BUNDLE_ICON_FILE "hexproof.icns"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}")

# Build the small native helper with the same source/version as the client.
# Java/Forge stay optional downloads for users. Building its adapter requires
# JDK 21+; it does not resolve Maven or rebuild the complete upstream reactor.
find_program(HEXPROOF_GO_EXECUTABLE go REQUIRED)
find_package(Python3 3.12 REQUIRED COMPONENTS Interpreter)
find_package(Java 21 REQUIRED COMPONENTS Development)
set(HEXPROOF_FORGE_OVERLAY_DIR "${CMAKE_CURRENT_BINARY_DIR}/forge-overlay" CACHE PATH
    "Build directory for the client-bundled Forge adapter")
file(GLOB_RECURSE HEXPROOF_FORGE_OVERLAY_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/native-host/src/main/java/*.java")
add_custom_command(
    OUTPUT "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar"
           "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.json"
    COMMAND "${Python3_EXECUTABLE}"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/build-overlay.py"
        --output "${HEXPROOF_FORGE_OVERLAY_DIR}" --javac "${Java_JAVAC_EXECUTABLE}"
    DEPENDS ${HEXPROOF_FORGE_OVERLAY_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/build-overlay.py"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/overlay-base.json"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/native-host/upstream.json"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/forge-runtime/native-host/native-hooks.patch"
        "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/runtimepkg/manifest.json"
    VERBATIM)
file(GLOB_RECURSE HEXPROOF_HOST_GO_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/homenode/*.go"
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/peerlink/*.go"
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/forgehost/*.go"
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/runtimepkg/*"
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/rulesengine/forge/*.go"
    "${CMAKE_CURRENT_SOURCE_DIR}/../server/cmd/hexproof-forge-host/*.go")
set(HEXPROOF_HOST_HELPER "${CMAKE_CURRENT_BINARY_DIR}/host-helper/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}")
set(HEXPROOF_HOST_LDFLAGS "-X hexproof/server/internal/buildinfo.Version=${PROJECT_VERSION}")
if(WIN32)
    string(APPEND HEXPROOF_HOST_LDFLAGS " -H windowsgui")
endif()
add_custom_command(OUTPUT "${HEXPROOF_HOST_HELPER}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/host-helper"
    COMMAND "${Python3_EXECUTABLE}"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/build-forge-helper.py"
        --go "${HEXPROOF_GO_EXECUTABLE}" "--ldflags=${HEXPROOF_HOST_LDFLAGS}"
        --output "${HEXPROOF_HOST_HELPER}" --overlay-dir "${HEXPROOF_FORGE_OVERLAY_DIR}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../server"
    DEPENDS ${HEXPROOF_HOST_GO_SOURCES}
        "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/build-forge-helper.py"
        "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar"
        "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.json"
        "${CMAKE_CURRENT_SOURCE_DIR}/../server/go.mod"
        "${CMAKE_CURRENT_SOURCE_DIR}/../server/go.sum"
        "${CMAKE_CURRENT_SOURCE_DIR}/../server/internal/buildinfo/buildinfo.go"
    VERBATIM)
add_custom_target(hexproof_forge_host ALL
    DEPENDS "${HEXPROOF_HOST_HELPER}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_FILE_DIR:hexproof>"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${HEXPROOF_HOST_HELPER}" "$<TARGET_FILE_DIR:hexproof>/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar" "$<TARGET_FILE_DIR:hexproof>/forge-overlay.jar")
add_dependencies(hexproof hexproof_forge_host)
if(TARGET hexproof_native_audit)
    add_dependencies(hexproof_native_audit hexproof_forge_host)
    add_custom_command(TARGET hexproof_native_audit POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${HEXPROOF_HOST_HELPER}" "$<TARGET_FILE_DIR:hexproof_native_audit>/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar" "$<TARGET_FILE_DIR:hexproof_native_audit>/forge-overlay.jar")
endif()
if(APPLE)
    install(PROGRAMS "${HEXPROOF_HOST_HELPER}" DESTINATION "hexproof.app/Contents/MacOS")
    install(FILES "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar" DESTINATION "hexproof.app/Contents/MacOS")
else()
    install(PROGRAMS "${HEXPROOF_HOST_HELPER}" DESTINATION bin)
    install(FILES "${HEXPROOF_FORGE_OVERLAY_DIR}/forge-overlay.jar" DESTINATION bin)
endif()

install(TARGETS hexproof
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin)

# vcpkg places non-Qt runtime DLLs such as zlib beside the built executable.
# Qt's deployment tool handles Qt itself; retain those app-local DLLs when
# installing the Windows portable package.
if(WIN32)
    install(DIRECTORY "$<TARGET_FILE_DIR:hexproof>/"
        DESTINATION bin
        FILES_MATCHING
        PATTERN "*.dll")
endif()

if(UNIX AND NOT APPLE)
    install(DIRECTORY "${HEXPROOF_ICONS_DIR}/hicolor/"
        DESTINATION share/icons/hicolor)
    install(FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/../../packaging/linux/io.github.claystan404.hexproof.desktop"
        DESTINATION share/applications)
endif()

install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../THIRD-PARTY-NOTICES.md"
    DESTINATION .)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/assets/mana/OFL.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/assets/mana/README.md"
    DESTINATION licenses/mana)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/README.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/manifest.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/Kenney-Casino-License.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/Kenney-Interface-License.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/audio/Kenney-Impact-License.txt"
    DESTINATION licenses/audio)
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/music/README.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/music/manifest.json"
    DESTINATION licenses/music)

# Qt 6.8's generic Linux deployment does not select the
# platforminputcontexts plugin category automatically. Keep the plugins that
# ship with the selected Qt build beside the portable client so qt.conf does
# not prevent packaged builds from using IBus or Compose input.
set(HEXPROOF_LINUX_INPUT_CONTEXT_MODULES "")
if(UNIX AND NOT APPLE)
    foreach(plugin_target IN ITEMS
            Qt6::QComposePlatformInputContextPlugin
            Qt6::QIbusPlatformInputContextPlugin)
        if(TARGET ${plugin_target})
            install(FILES "$<TARGET_FILE:${plugin_target}>"
                DESTINATION "${QT6_INSTALL_PLUGINS}/platforminputcontexts")
            string(APPEND HEXPROOF_LINUX_INPUT_CONTEXT_MODULES
                "\n        \"$<TARGET_FILE:${plugin_target}>\"")
        endif()
    endforeach()
endif()

# Collect the platform Qt runtime, QML imports, and plugins into install trees
# produced by the release scripts under packaging/.
qt_generate_deploy_qml_app_script(
    TARGET hexproof
    OUTPUT_SCRIPT hexproof_deploy_script
    NO_TRANSLATIONS
    NO_UNSUPPORTED_PLATFORM_ERROR)

if(UNIX AND NOT APPLE)
    # Arch installs both Qt and system libraries under /usr/lib. Qt's default
    # Linux exclusion only covers /lib, so use a filtered runtime-dependency
    # call that keeps Qt relocatable without bundling an incompatible libc.
    get_filename_component(
        hexproof_deploy_script_dir "${hexproof_deploy_script}" DIRECTORY)
    set(hexproof_linux_deploy_script
        "${hexproof_deploy_script_dir}/deploy_qml_app_hexproof_linux.cmake")
    set(hexproof_linux_deploy_script_content [=[
set(CMAKE_POLICY_DEFAULT_CMP0207 NEW)
if(POLICY CMP0207)
    cmake_policy(SET CMP0207 NEW)
endif()
include("${CMAKE_CURRENT_LIST_DIR}/QtDeploySupport.cmake")
if(POLICY CMP0207)
    cmake_policy(SET CMP0207 NEW)
endif()
include("${CMAKE_CURRENT_LIST_DIR}/hexproof-plugins.cmake" OPTIONAL)

qt6_deploy_qml_imports(TARGET hexproof PLUGINS_FOUND plugins_found)
qt6_deploy_runtime_dependencies(
    EXECUTABLE "$<TARGET_FILE:hexproof>"
    ADDITIONAL_MODULES ${plugins_found}
@HEXPROOF_LINUX_INPUT_CONTEXT_MODULES@
    GENERATE_QT_CONF
    NO_TRANSLATIONS
    POST_INCLUDE_REGEXES ".*/libQt6[^/]*[.]so([.].*)?$"
    POST_EXCLUDE_REGEXES
        "^/lib/"
        "^/lib64/"
        "^/usr/lib/"
        "^/usr/lib64/")
]=])
    string(CONFIGURE "${hexproof_linux_deploy_script_content}"
        hexproof_linux_deploy_script_content @ONLY)
    file(GENERATE OUTPUT "${hexproof_linux_deploy_script}"
        CONTENT "${hexproof_linux_deploy_script_content}")
    install(SCRIPT "${hexproof_linux_deploy_script}")
else()
    install(SCRIPT "${hexproof_deploy_script}")
endif()

# --- Offline card database builder ---

add_executable(hexproof_card_database_builder EXCLUDE_FROM_ALL
    ../../tools/card-database-builder/main.cpp
    src/deck/Deck.cpp
)
target_include_directories(hexproof_card_database_builder PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_card_database_builder PRIVATE
    hexproof_card_services
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Quick
    Qt6::Sql
    ZLIB::ZLIB)

# --- Client tests ---

enable_testing()

if(HEXPROOF_BUILD_NATIVE_AUDIT)
    qt_add_executable(hexproof_native_audit_test
        tests/native_audit_test.cpp
        src/testing/NativeAudit.cpp
        src/testing/NativeAudit.h)
    target_include_directories(hexproof_native_audit_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(hexproof_native_audit_test PRIVATE hexproof_session Qt6::Quick Qt6::Test)
    add_test(NAME native_audit_adapter COMMAND hexproof_native_audit_test)
    # Adapter regression tests are component tests; real scenario runs use the
    # dedicated executable on a native display through the external runner.
    set_tests_properties(native_audit_adapter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

qt_add_executable(hexproof_profilelock_test tests/profilelock_test.cpp)
target_include_directories(hexproof_profilelock_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_profilelock_test PRIVATE Qt6::Core Qt6::Test)
add_test(NAME profilelock COMMAND hexproof_profilelock_test)

qt_add_executable(hexproof_audio_test
    tests/audio_controller_test.cpp
    src/services/AudioController.cpp
    src/services/AudioController.h)
target_include_directories(hexproof_audio_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_audio_test PRIVATE Qt6::Core Qt6::Multimedia Qt6::Test)
add_test(NAME audio COMMAND hexproof_audio_test)
qt_add_executable(hexproof_music_test
    tests/music_controller_test.cpp
    src/services/BackgroundMusicController.cpp
    src/services/BackgroundMusicController.h)
target_include_directories(hexproof_music_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_music_test PRIVATE Qt6::Core Qt6::Multimedia Qt6::Test)
add_test(NAME music COMMAND hexproof_music_test)

if(UNIX AND NOT APPLE)
    add_test(NAME desktop-install
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../../packaging/linux/test-install-desktop.sh")
endif()

qt_add_executable(hexproof_test
    tests/protocol_test.cpp
)
target_include_directories(hexproof_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_test PRIVATE
    HEXPROOF_PROTOCOL_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../testdata/protocol/v1")
target_link_libraries(hexproof_test PRIVATE Qt6::Core Qt6::Test)
add_test(NAME protocol COMMAND hexproof_test)

qt_add_executable(hexproof_wsclient_test
    tests/wsclient_test.cpp
    tests/wsclient_commands_test.cpp
    tests/wsclient_rules_start_failure_test.cpp
    tests/wsclient_endpoints_test.cpp
    tests/wsclient_tournament_test.cpp
    tests/wsclient_reconnect_test.cpp
    tests/wsclient_test.h
)
target_include_directories(hexproof_wsclient_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_wsclient_test PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}"
    HEXPROOF_PROTOCOL_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../testdata/protocol/v1")
target_link_libraries(hexproof_wsclient_test PRIVATE
    hexproof_session
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Test
    Qt6::WebSockets)
qt_add_resources(hexproof_wsclient_test "wsclient_server_directory"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME wsclient COMMAND hexproof_wsclient_test)

qt_add_executable(hexproof_hubtransport_test tests/hubtransport_test.cpp)
target_link_libraries(hexproof_hubtransport_test PRIVATE hexproof_session Qt6::Test)
target_compile_definitions(hexproof_hubtransport_test PRIVATE HEXPROOF_VERSION="${PROJECT_VERSION}")
set_target_properties(hexproof_hubtransport_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/../hubtransport-test")
add_custom_command(TARGET hexproof_hubtransport_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:hexproof_hubtransport_test>"
        "$<TARGET_FILE_DIR:hexproof_hubtransport_test>/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}"
    VERBATIM)
qt_add_resources(hexproof_hubtransport_test "hubtransport_server_directory"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME hubtransport COMMAND hexproof_hubtransport_test)
set_tests_properties(hubtransport PROPERTIES TIMEOUT 60)

qt_add_executable(hexproof_forgehostservice_test tests/forgehostservice_test.cpp)
target_link_libraries(hexproof_forgehostservice_test PRIVATE hexproof_session Qt6::Test)
# Keep the fixture helper outside the real client's deployment directory.
set_target_properties(hexproof_forgehostservice_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/../forgehostservice-test")
add_custom_command(TARGET hexproof_forgehostservice_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:hexproof_forgehostservice_test>"
        "$<TARGET_FILE_DIR:hexproof_forgehostservice_test>/hexproof-forge-host${CMAKE_EXECUTABLE_SUFFIX}"
    VERBATIM)
add_test(NAME forgehostservice COMMAND hexproof_forgehostservice_test)
set_tests_properties(forgehostservice PROPERTIES TIMEOUT 90)

qt_add_executable(hexproof_modelopponentservice_test tests/modelopponentservice_test.cpp)
target_link_libraries(hexproof_modelopponentservice_test PRIVATE hexproof_session Qt6::Test)
add_test(NAME modelopponentservice COMMAND hexproof_modelopponentservice_test)
set_tests_properties(modelopponentservice PROPERTIES TIMEOUT 90)

qt_add_executable(hexproof_localtestsession_test tests/localtestsession_test.cpp)
target_compile_definitions(hexproof_localtestsession_test PRIVATE
    HEXPROOF_DEFAULT_SERVER_BINARY="${CMAKE_CURRENT_SOURCE_DIR}/../../build/server/hexproof-server")
target_link_libraries(hexproof_localtestsession_test PRIVATE hexproof_local_test Qt6::Test)
qt_add_resources(hexproof_localtestsession_test "localtest_server_directory"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME localtestsession COMMAND hexproof_localtestsession_test)
set_tests_properties(localtestsession PROPERTIES LABELS integration TIMEOUT 45)

qt_add_executable(hexproof_server_integration_test
    tests/server_integration_test.cpp
)
target_include_directories(hexproof_server_integration_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_server_integration_test PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}"
    HEXPROOF_DEFAULT_SERVER_BINARY="${CMAKE_CURRENT_SOURCE_DIR}/../../build/server/hexproof-server")
target_link_libraries(hexproof_server_integration_test PRIVATE
    hexproof_session
    hexproof_table_models
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Test
    Qt6::WebSockets)
qt_add_resources(hexproof_server_integration_test "integration_server_directory"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME server-integration COMMAND hexproof_server_integration_test)
set_tests_properties(server-integration PROPERTIES
    LABELS integration
    TIMEOUT 30)

qt_add_executable(hexproof_serverdirectory_test
    tests/serverdirectory_test.cpp
)
target_include_directories(hexproof_serverdirectory_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_serverdirectory_test PRIVATE
    hexproof_session
    Qt6::Core
    Qt6::Network
    Qt6::Test)
qt_add_resources(hexproof_serverdirectory_test "serverdirectory_config"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME serverdirectory COMMAND hexproof_serverdirectory_test)

qt_add_executable(hexproof_reconnectcontroller_test
    tests/reconnectcontroller_test.cpp
)
target_include_directories(hexproof_reconnectcontroller_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_reconnectcontroller_test PRIVATE
    hexproof_session
    Qt6::Core
    Qt6::Network
    Qt6::Test)
qt_add_resources(hexproof_reconnectcontroller_test "reconnect_server_directory"
    PREFIX "/"
    FILES "${HEXPROOF_SERVER_DIRECTORY_RESOURCE}")
add_test(NAME reconnectcontroller COMMAND hexproof_reconnectcontroller_test)

qt_add_executable(hexproof_protocolsession_test
    tests/protocolsession_test.cpp
)
target_include_directories(hexproof_protocolsession_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_protocolsession_test PRIVATE
    hexproof_session
    Qt6::Core
    Qt6::Test)
add_test(NAME protocolsession COMMAND hexproof_protocolsession_test)

qt_add_executable(hexproof_forgereplay_test tests/forgereplay_test.cpp)
target_link_libraries(hexproof_forgereplay_test PRIVATE hexproof_session Qt6::Test)
add_test(NAME forgereplay COMMAND hexproof_forgereplay_test)

qt_add_executable(hexproof_limiteddeckdraftstore_test tests/limiteddeckdraftstore_test.cpp)
target_link_libraries(hexproof_limiteddeckdraftstore_test PRIVATE hexproof_session Qt6::Test)
add_test(NAME limiteddeckdraftstore COMMAND hexproof_limiteddeckdraftstore_test)

qt_add_executable(hexproof_deck_test
    tests/deck_test.cpp
    tests/deck_model_test.cpp
    tests/deck_printing_identity_test.cpp
    tests/deck_test.h
    src/models/ClientPreferencesModel.cpp
)
target_include_directories(hexproof_deck_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_deck_test PRIVATE HEXPROOF_TESTING)
target_link_libraries(hexproof_deck_test PRIVATE
    hexproof_deck_library
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Test)
add_test(NAME deck COMMAND hexproof_deck_test)

qt_add_executable(hexproof_decklegality_test
    tests/decklegality_test.cpp
)
target_include_directories(hexproof_decklegality_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_decklegality_test PRIVATE
    hexproof_card_services
    Qt6::Concurrent
    Qt6::Core
    Qt6::Sql
    Qt6::Test)
add_test(NAME decklegality COMMAND hexproof_decklegality_test)

qt_add_executable(hexproof_gametablemodel_test
    tests/gametablemodel_test.cpp
)
target_include_directories(hexproof_gametablemodel_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_gametablemodel_test PRIVATE
    HEXPROOF_PROTOCOL_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../testdata/protocol/v1")
target_link_libraries(hexproof_gametablemodel_test PRIVATE
    hexproof_table_models
    Qt6::Core
    Qt6::Test)
add_test(NAME gametablemodel COMMAND hexproof_gametablemodel_test)

qt_add_executable(hexproof_optimisticcommandmodel_test
    tests/optimisticcommandmodel_test.cpp
)
target_include_directories(hexproof_optimisticcommandmodel_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_optimisticcommandmodel_test PRIVATE
    hexproof_table_models
    Qt6::Core
    Qt6::Test)
add_test(NAME optimisticcommandmodel COMMAND
    hexproof_optimisticcommandmodel_test)

qt_add_executable(hexproof_sideboardtablemodel_test
    tests/sideboardtablemodel_test.cpp
)
target_include_directories(hexproof_sideboardtablemodel_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_sideboardtablemodel_test PRIVATE
    hexproof_table_models
    Qt6::Core
    Qt6::Test)
add_test(NAME sideboardtablemodel COMMAND
    hexproof_sideboardtablemodel_test)

qt_add_executable(hexproof_cardcatalog_test
    tests/cardcatalog_test.cpp
    tests/cardcatalog_cache_priority_test.cpp
    tests/cardcatalog_parallel_test.cpp
    tests/cardcatalog_database_test.cpp
    tests/cardcatalog_localized_text_test.cpp
    tests/cardcatalog_limited_art_test.cpp
    tests/cardcatalog_match_expansion_test.cpp
    tests/cardcatalog_test.h
)
target_include_directories(hexproof_cardcatalog_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_cardcatalog_test PRIVATE
    hexproof_deck_library
    hexproof_card_services
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Quick
    Qt6::Sql
    Qt6::Test
    ZLIB::ZLIB)
add_test(NAME cardcatalog COMMAND hexproof_cardcatalog_test)

qt_add_executable(hexproof_cardimageprovider_test tests/cardimageprovider_test.cpp)
target_link_libraries(hexproof_cardimageprovider_test PRIVATE
    hexproof_card_services Qt6::Quick Qt6::Test)
add_test(NAME cardimageprovider COMMAND hexproof_cardimageprovider_test)
set_tests_properties(cardimageprovider PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
add_test(NAME bounded-catalog-source
    COMMAND ${CMAKE_COMMAND}
        -DHEXPROOF_CLIENT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/bounded_catalog_source_test.cmake)

qt_add_executable(hexproof_catalogrepository_test
    tests/catalogrepository_test.cpp
)
target_include_directories(hexproof_catalogrepository_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_catalogrepository_test PRIVATE
    hexproof_card_services
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Sql
    Qt6::Test
    ZLIB::ZLIB)
add_test(NAME catalogrepository COMMAND hexproof_catalogrepository_test)

qt_add_executable(hexproof_cardservices_test
    tests/cardservices_test.cpp
)
target_include_directories(hexproof_cardservices_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(hexproof_cardservices_test PRIVATE
    HEXPROOF_VERSION="${PROJECT_VERSION}")
target_link_libraries(hexproof_cardservices_test PRIVATE
    hexproof_card_services
    Qt6::Core
    Qt6::Network
    Qt6::Test)
add_test(NAME cardservices COMMAND hexproof_cardservices_test)

qt_add_executable(hexproof_cardartmanager_test
    tests/cardartmanager_test.cpp
)
target_include_directories(hexproof_cardartmanager_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_cardartmanager_test PRIVATE
    hexproof_card_services
    Qt6::Concurrent
    Qt6::Core
    Qt6::Gui
    Qt6::Test)
add_test(NAME cardartmanager COMMAND hexproof_cardartmanager_test)

qt_add_executable(hexproof_cardartstorage_test tests/cardartstorage_test.cpp)
target_link_libraries(hexproof_cardartstorage_test PRIVATE hexproof_card_services Qt6::Test)
add_test(NAME cardartstorage COMMAND hexproof_cardartstorage_test)

qt_add_executable(hexproof_customcardartstore_test tests/customcardartstore_test.cpp)
target_link_libraries(hexproof_customcardartstore_test PRIVATE hexproof_card_services Qt6::Test)
add_test(NAME customcardartstore COMMAND hexproof_customcardartstore_test)

qt_add_executable(hexproof_cardcatalog_customart_test tests/cardcatalog_customart_test.cpp)
target_link_libraries(hexproof_cardcatalog_customart_test PRIVATE
    hexproof_card_services hexproof_deck_library Qt6::Test)
add_test(NAME cardcatalog-customart COMMAND hexproof_cardcatalog_customart_test)

qt_add_executable(hexproof_cardartarchive_test
    tests/cardartarchive_test.cpp
)
target_include_directories(hexproof_cardartarchive_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_cardartarchive_test PRIVATE
    hexproof_card_services
    Qt6::Core
    Qt6::Gui
    Qt6::Test)
add_test(NAME cardartarchive COMMAND hexproof_cardartarchive_test)

qt_add_executable(hexproof_appupdate_test
    tests/appupdateservice_test.cpp
)
target_include_directories(hexproof_appupdate_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_appupdate_test PRIVATE
    hexproof_update_service
    Qt6::Core
    Qt6::Network
    Qt6::Test)
add_test(NAME appupdate COMMAND hexproof_appupdate_test)

qt_add_executable(hexproof_matchload_test
    tests/matchload_test.cpp
    src/services/MatchCardCacheBinding.cpp
    src/services/MatchLoadCoordinator.cpp
)
target_include_directories(hexproof_matchload_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_matchload_test PRIVATE
    hexproof_table_models
    hexproof_session
    hexproof_card_services
    Qt6::Core
    Qt6::Test)
add_test(NAME matchload COMMAND hexproof_matchload_test)

qt_add_executable(hexproof_qml_test
    tests/qmltest_main.cpp
    src/models/ClientPreferencesModel.cpp
    src/services/TranslationController.cpp
)
target_include_directories(hexproof_qml_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(hexproof_qml_test PRIVATE
    hexproof_content_service
    hexproof_session
    hexproof_deck_library
    hexproof_table_models
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickEffects
    Qt6::QuickTest)

qt_add_executable(hexproof_publiccontent_test tests/publiccontent_test.cpp)
target_link_libraries(hexproof_publiccontent_test PRIVATE hexproof_content_service Qt6::Test)
add_test(NAME publiccontent COMMAND hexproof_publiccontent_test)
qt_add_shaders(hexproof_qml_test "liquidglass_shaders_test"
    BATCHABLE
    PRECOMPILE
    OPTIMIZED
    PREFIX "/shaders"
    FILES
        qml/shaders/liquidglass.frag)
qt_add_resources(hexproof_qml_test "qml_test_translations"
    PREFIX "/i18n"
    BASE "${CMAKE_CURRENT_BINARY_DIR}"
    FILES
        ${HEXPROOF_UI_QM_FILE}
        ${HEXPROOF_DYNAMIC_QM_FILES})
if(WIN32)
    set(HEXPROOF_QML_TEXT_LOG
        "${CMAKE_CURRENT_BINARY_DIR}/qml-test-results.txt")
else()
    set(HEXPROOF_QML_TEXT_LOG "-")
endif()
add_test(NAME qml COMMAND hexproof_qml_test
    -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/qml
    -import ${CMAKE_CURRENT_SOURCE_DIR}/qml
    -o ${HEXPROOF_QML_TEXT_LOG},txt
    -o ${CMAKE_CURRENT_BINARY_DIR}/qml-test-results.xml,junitxml
    -v1)
set_tests_properties(qml PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Context properties are an intentional part of the current QML integration,
# but syntax, type, import, and layout diagnostics must remain clean.
file(GLOB_RECURSE HEXPROOF_QML_LINT_FILES CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/qml/*.qml)
if(TARGET Qt6::qmllint)
    set(HEXPROOF_QMLLINT_COMMAND $<TARGET_FILE:Qt6::qmllint>)
else()
    find_program(HEXPROOF_QMLLINT_COMMAND NAMES qmllint
        HINTS ${QT6_HOST_INFO_BINDIR})
endif()
if(HEXPROOF_QMLLINT_COMMAND)
    set(HEXPROOF_QMLLINT_OPTIONS
        --unqualified disable
        --missing-property warning)
    if(Qt6_VERSION VERSION_GREATER_EQUAL "6.10.0")
        list(APPEND HEXPROOF_QMLLINT_OPTIONS --context-properties disable)
    endif()
    add_test(NAME qmllint COMMAND ${HEXPROOF_QMLLINT_COMMAND}
        ${HEXPROOF_QMLLINT_OPTIONS}
        -W 0
        -I ${CMAKE_CURRENT_SOURCE_DIR}/qml
        ${HEXPROOF_QML_LINT_FILES})
endif()
