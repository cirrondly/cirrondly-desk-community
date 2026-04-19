# Cleanup Report

Scanned source/config files under `CirrondlyDesk/` for backend URLs, Pro-only services, telemetry, team-only UI, hardcoded identifiers, and internal-only references.

## CirrondlyDesk/App/AppDelegate.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/App/CirrondlyDeskApp.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/App/DependencyContainer.swift
- Issues found: references to CirrondlyAPIClient, TeamEnrollmentService, ReportingScheduler, and AnalyticsHeartbeat.
- Action taken: removed backend, team-enrollment, reporting, and telemetry dependencies from the container wiring.

## CirrondlyDesk/Core/Models/BurnRate.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/CostEstimate.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/DailyCell.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/ModelFamily.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/ProviderProfile.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/ProviderResult.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/SessionWindow.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Models/UsageSnapshot.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/AiderProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/AmpProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/AntigravityProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/ClaudeCodeProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/ClaudeSubscriptionProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/CodexProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/ContinueProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/CopilotProvider.swift
- Issues found: clean for Pro leakage; final build exposed an async enumerator warning.
- Action taken: refactored transcript enumeration into a synchronous helper to eliminate the build warning.

## CirrondlyDesk/Core/Providers/CursorProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/FactoryProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/GeminiProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/JetBrainsAIProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/KimiProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/KiroProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/MiniMaxProvider.swift
- Issues found: clean for Pro leakage; final build exposed an unused local warning.
- Action taken: removed the unused local to keep the build warning-free.

## CirrondlyDesk/Core/Providers/OpenCodeGoProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/PerplexityProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/ProviderRegistry.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/SyntheticProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/UsageProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/WindsurfProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Providers/ZAIProvider.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/BurnRateCalculator.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/KeychainService.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/LaunchAtLoginService.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/NotificationService.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/PollingManager.swift
- Issues found: reference to ReportingScheduler.
- Action taken: removed reporting scheduler dependency and related calls.

## CirrondlyDesk/Core/Services/ServiceStatusMonitor.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/StatusLineExporter.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/UpdateChecker.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/UsageAggregator.swift
- Issues found: leftover reporting export using UsageReportSession.
- Action taken: removed the reporting-only session export method.

## CirrondlyDesk/Core/Utils/JSONLStreamReader.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Utils/JWTUtilities.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Utils/SQLiteReader.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Utils/TimeHelpers.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/MenuBar/PopoverHost.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/MenuBar/StatusBarController.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/MenuBar/StatusIconRenderer.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Resources/Assets.xcassets/CloudLogo.imageset/Contents.json
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Resources/Assets.xcassets/Contents.json
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Resources/provider-brands.json
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Onboarding/AllSetView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Onboarding/DetectedProvidersView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Onboarding/WelcomeView.swift
- Issues found: copy mentioned paid workspace and team reporting.
- Action taken: rewrote onboarding copy to local-only, no-telemetry language.

## CirrondlyDesk/Views/Popover/BurnRateIndicator.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/ContributionHeatmap.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/FooterActionsView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/HeaderView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/PopoverRootView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/ProviderRowView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/SessionProgressBar.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/TimeToResetBadge.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/TodayCostView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Popover/WeeklyProgressBar.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Settings/AboutTab.swift
- Issues found: copy implied workspace syncing, public repository links targeted the old repo path, and the allowed Desk upsell footer was missing.
- Action taken: removed workspace-sync wording, updated repo links to `github.com/cirrondly/cirrondly-desk-community`, and added the approved Desk footer.

## CirrondlyDesk/Views/Settings/AdvancedTab.swift
- Issues found: telemetry heartbeat opt-out UI and copy remained in Community.
- Action taken: removed telemetry controls and updated the tab copy to local-only integrations.

## CirrondlyDesk/Views/Settings/GeneralTab.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Settings/NotificationsTab.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Settings/ProfilesTab.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Settings/SettingsScene.swift
- Issues found: Team tab is absent, but the settings navigation still used the internal "Providers" label and did not expose the existing profiles tab.
- Action taken: kept Team absent, renamed the tab label to "Sources", and added the Profiles tab to the public settings surface.

## CirrondlyDesk/Views/Settings/SourcesTab.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Shared/ProviderBrandCatalog.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Shared/ProviderIcons.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Shared/ProviderServiceStatusView.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Theme/CirrondlyColors.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Theme/GradientBackground.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Theme/Spacing.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Views/Theme/Typography.swift
- Issues found: clean.
- Action taken: none.

## CirrondlyDesk/Core/Services/AnalyticsHeartbeat.swift
- Issues found: telemetry heartbeat stub remained in Community.
- Action taken: deleted the file.

## CirrondlyDesk/Core/Services/CirrondlyAPIClient.swift
- Issues found: Cirrondly backend client, remote enrollment/reporting payloads, and backend URL references.
- Action taken: deleted the file.

## CirrondlyDesk/Core/Services/ReportingScheduler.swift
- Issues found: hourly reporting flow to the Cirrondly backend.
- Action taken: deleted the file.

## CirrondlyDesk/Core/Services/TeamEnrollmentService.swift
- Issues found: team enrollment state, workspace persistence, and paid backend flow.
- Action taken: deleted the file.

## CirrondlyDesk/Core/Utils/MachineIDHasher.swift
- Issues found: machine identifier hashing used by backend reporting.
- Action taken: deleted the file.

## CirrondlyDesk/Views/Settings/TeamTab.swift
- Issues found: Pro-only team enrollment UI and Cirrondly help link.
- Action taken: deleted the file.
