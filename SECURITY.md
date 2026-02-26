# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.2.x   | Yes       |
| < 2.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public GitHub issue**
2. Email: kochj23 (via GitHub)
3. Include: description, steps to reproduce, potential impact

We aim to respond within 48 hours and provide a fix within 7 days for critical issues.

## Security Features

- **Local Processing**: All email parsing and AI analysis runs on-device
- **No Cloud Upload**: Email data never leaves your machine
- **Read-Only Access**: MBox files are read, never modified
- **No Telemetry**: Zero analytics, crash reporting, or usage tracking
- **Keychain Storage**: Any API keys stored in macOS Keychain

## Data Privacy

MBox Explorer processes potentially sensitive email archives. We take this seriously:

- Email content is parsed in-memory and never cached to disk beyond the session
- AI search queries are processed locally via Ollama/MLX
- No email metadata is transmitted anywhere
- RAG exports are saved only where you specify

## Best Practices

- Never hardcode credentials or API keys
- Report suspicious behavior immediately
- Keep dependencies updated
- Review all code changes for security implications
