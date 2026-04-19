# Security Policy

## Supported versions

Only the latest release on the `main` branch receives security updates.

## Reporting a vulnerability

Please do NOT open a public GitHub issue for security vulnerabilities.

Email: security@cirrondly.com

Include:
- Description of the issue
- Steps to reproduce
- macOS version
- App version
- Potential impact

You will receive a reply within 5 business days. If the vulnerability is
confirmed, we coordinate disclosure timing with you and credit you in the fix
commit (unless you prefer to stay anonymous).

## Scope

In scope:
- Code execution, privilege escalation, or data leakage via the app
- Keychain access issues
- Unintended network calls (the app is local-only)

Out of scope:
- Social engineering
- Physical access attacks
- Vulnerabilities in third-party providers (Claude, Cursor, etc.) that the app
  merely reads data from