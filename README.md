# Cirrondly Desk

Cirrondly Desk is a native macOS menu bar app that tracks AI coding tool usage across local providers and can optionally report encrypted metrics to a paid Cirrondly workspace.

## Current scaffold

- Native menu bar shell built with AppKit and SwiftUI
- Branded popover and settings window using Cirrondly colors
- Local provider modules for Claude Code, Codex, Continue, Aider, Cursor, and Claude subscription
- Optional team enrollment and hourly usage reporting boundary
- Local statusline export to `~/.cirrondly/usage.json`
- GitHub Actions release workflow scaffold for notarized DMG releases

## Notes

- The bundled font files and final cloud artwork are not checked in yet. The app falls back to system fonts until those assets are added.
- Several providers are detected but still use placeholder probe results where local schemas are unstable or not yet finalized.
- The paid/free boundary is preserved: no requests are made to `api.cirrondly.com` unless the user explicitly enrolls.

## Build

Open `CirrondlyDesk.xcodeproj` in Xcode 16+ and build the `CirrondlyDesk` target on macOS 15 or later.
