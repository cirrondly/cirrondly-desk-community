# Public release checklist

Before pushing `cirrondly_desk_community/` to `github.com/cirrondly/cirrondly-desk-community`:

- [ ] Verify `LICENSE`, `NOTICE`, `TRADEMARKS.md`, `CONTRIBUTING.md`,
      `CODE_OF_CONDUCT.md`, `README.md`, `SECURITY.md`, `CHANGELOG.md` exist
      at repo root.
- [ ] Verify `.github/` directory has ISSUE_TEMPLATE, PULL_REQUEST_TEMPLATE,
      and ci.yml.
- [ ] Bundle ID in Info.plist is `com.cirrondly.desk.community`.
- [ ] Display name is `Cirrondly Desk Community`.
- [ ] `grep -r "api.cirrondly\|ws_\|TeamEnrollment" CirrondlyDesk/` returns
      zero.
- [ ] App builds with `xcodebuild` in CI-like clean state.
- [ ] Screenshots added to `docs/` (hero.png referenced in README).
- [ ] CLEANUP_REPORT.md reviewed and no issues remain.

## Manual steps (owner does these)

1. `cd cirrondly_desk_community/`
2. Delete `.git/` if it exists (fresh history).
3. `git init -b main`
4. `git add .`
5. `git commit -s -m "Initial public release — Cirrondly Desk Community v0.1.0"`
6. Create GitHub repo at `github.com/cirrondly/cirrondly-desk-community` (public, no README, no
   LICENSE — we provide them).
7. `git remote add origin git@github.com:cirrondly/cirrondly-desk-community.git`
8. `git push -u origin main`
9. Tag `v0.1.0`: `git tag -s v0.1.0 -m "v0.1.0 — Initial public release"`
10. `git push origin v0.1.0`
11. Create GitHub Release from the v0.1.0 tag with release notes copied from
    CHANGELOG.md.
12. Enable branch protection on `main` (require PR + CI).
13. Enable GitHub Discussions.
14. Publish the signed `.dmg` in GitHub Releases and keep the latest release notes updated.