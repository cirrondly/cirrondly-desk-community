# Contributing to Cirrondly Desk Community

Thanks for your interest in contributing.

## Ways to contribute

- **Report bugs**: open a GitHub Issue with reproduction steps, macOS version,
  and which providers you have installed.
- **Suggest features**: open a GitHub Issue tagged `enhancement`. Note that
  features specific to team/organization analytics belong in Cirrondly Desk
  (the commercial version), not here.
- **Add a provider**: see "Adding a provider" below.
- **Fix a bug**: open a pull request. See "Pull request process" below.

## Adding a provider

1. Implement the `UsageProvider` protocol in a new file under
   `CirrondlyDesk/Core/Providers/`.
2. Register it in `ProviderRegistry.swift`.
3. Add the provider's SVG icon to `CirrondlyDesk/Resources/ProviderIcons/`.
4. Update `CirrondlyDesk/Resources/provider-brands.json` with the brand metadata.
5. Add unit tests covering at least: `isAvailable()` detection, `probe()` happy
   path, `probe()` when the provider is installed but has no recent usage.

## Pull request process

1. **Sign off your commits** with `git commit -s`. This asserts the Developer
   Certificate of Origin (DCO, see `https://developercertificate.org`).
   Unsigned commits will not be merged.
2. Target the `main` branch.
3. Describe what and why in the PR body.
4. If the PR changes UI, attach before/after screenshots.
5. Keep PRs focused. One feature or fix per PR.
6. Be patient — reviews may take a few days.

## Scope boundaries

Cirrondly Desk Community covers:
- Local usage tracking across AI coding tool providers
- Menu bar UI, popover, settings
- Local notifications and statusline export
- Local-network (LAN) peer discovery (future)

Cirrondly Desk Community does NOT cover:
- Remote peer synchronization across networks
- Team aggregation dashboards
- Cloud sync with the Cirrondly Agent platform
- Email/push alerts
- SSO, audit logs, priority support

Those features live in Cirrondly Desk (commercial). Pull requests that implement
those features here will be politely declined. Ask before investing time on
large PRs if you're unsure.

## Code style

- Swift standard formatting. Run the default Xcode formatter before committing.
- No third-party package dependencies. Apple frameworks only.
- Public APIs must have doc comments (`///`).

## License of contributions

By contributing, you agree that your contributions will be licensed under the
Apache License 2.0, the same license as the rest of the project.