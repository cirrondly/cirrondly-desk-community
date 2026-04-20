# Changelog

All notable changes to Cirrondly Desk Community are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/).

## [0.1.2] — 2026-04-20

### Added
- History button on every provider card that opens a standalone popup with a daily bar chart and a natural-language forecast to the next reset.
- Forecast block warnings when current pace is projected to exhaust the quota before the cycle resets.

### Changed
- Status chip redesign with a transparent background, subtle border, and dot-only health accent.
- Forced light appearance across the app. Dark mode support will arrive in a future release.

### Fixed
- Text illegibility when macOS appearance was set to Dark.

## [0.1.1] — 2026-04-20

### Fixed
- Copilot: now detects multiple GitHub accounts on the same Mac and exposes them as profiles.
- Reset date is now displayed on every provider that has a quota window — Copilot was previously missing it.

### Added
- Forecast captions on every progress bar: "At current pace: ~X% by reset" or "You'll run out in Xh Ym".

### Changed
- (Color adjustments handled manually by owner.)

## [0.1.0] — 2026-04-XX

### Added
- Initial public release.
- Support for 20+ AI coding tool providers.
- Menu bar icon with color-coded usage thresholds.
- Popover with today's cost, burn rate, session/weekly progress, 90-day heatmap.
- Settings: General, Notifications, Sources, Profiles, About.
- Local notifications at configurable thresholds.
- Statusline export to `~/.cirrondly/usage.json`.
- Multi-profile support per provider.