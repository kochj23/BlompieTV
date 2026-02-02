# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability within BlompieTV, please send an email to the repository owner. All security vulnerabilities will be promptly addressed.

Please include the following information:
- Type of vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Security Features

### Network Communication
- All communication with AI backends (Ollama/OpenWebUI) occurs over local network only
- No data is sent to external servers
- No user authentication or personal data is stored

### Data Storage
- Game saves are stored locally in UserDefaults
- No sensitive information is stored
- No credentials are required or stored

### Code Security
- No hardcoded secrets or API keys
- All network requests use standard URLSession
- Input validation on server addresses

## Best Practices for Users

1. **Network Security**: Ensure your local network is secured
2. **Server Trust**: Only connect to AI servers you trust and control
3. **Updates**: Keep the app and your AI backend up to date
