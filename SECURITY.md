# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 3.x     | ✅ Active support  |
| < 3.0   | ❌ Not supported   |

## What dream_opensearch Is Responsible For

dream_opensearch is a library that provides:
- **Client** - Sends HTTP requests to an OpenSearch cluster
- **Document operations** - Index, search, delete and bulk requests
- **Index management** - Create and delete indices
- **Query builders** - JSON strings for common queries

dream_opensearch is **not a framework**. You build the application. You decide what goes into each index and who can search it.

This means the security surface of dream_opensearch is small:
- Credential handling (the user name and password in the base URL)
- Request building (paths, headers and bodies that the client sends)
- JSON escaping in the query builders

## What You're Responsible For

Your application code handles:
- **Credentials** - Keep the base URL out of logs; it holds the user name and password
- **Index and document names** - The client puts them in the request path as you give them
- **Authorization** - You control who can read and write each index
- **Input validation** - Of everything you index or search for
- **TLS/HTTPS** - Use an `https://` base URL for a cluster on another host
- **Rate limiting** - Of the searches your users can start

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Email: **engineering@trustbound.ai**

### What to Include

- **Type of vulnerability** (e.g., credential leak, header injection)
- **Location** in the code of dream_opensearch (file/function)
- **Steps to reproduce** with minimal example
- **Impact** - What can an attacker do?
- **Proof-of-concept** if you have one

Focus on vulnerabilities in **the code of dream_opensearch**, not in your application code.

### What to Expect

1. **Acknowledgment** within 48 hours
2. **Assessment** within 7 days
3. **Fix** coordinated with you on timing
4. **Release** with security advisory
5. **Credit** in the advisory (if desired)

## Security in dream_opensearch

### Type Safety

Gleam's type system prevents many vulnerabilities:
- ✅ No null pointer exceptions
- ✅ No buffer overflows
- ✅ Exhaustive pattern matching
- ✅ Immutable data structures

### What dream_opensearch Does

- Sends the user name and password of the base URL only in the `authorization` header, never in the request line or the `host` header
- Keeps the user name and password out of every error message
- Escapes field names and values in the query builders, so a value cannot change the structure of the query JSON

### What dream_opensearch Doesn't Do

dream_opensearch provides no built-in:
- ❌ Escaping of index names or document IDs in the request path
- ❌ Authorization checks
- ❌ Input sanitization
- ❌ Rate limiting
- ❌ Retries

This is intentional. dream_opensearch provides building blocks. You compose them.

## Known Non-Issues

These are not dream_opensearch vulnerabilities (they're your application's responsibility):

- A base URL with credentials written to a log by your application
- Index names or document IDs taken from user input without validation
- Missing authorization checks
- HTTPS not configured for a remote cluster
- Missing rate limiting

## Dependencies

dream_opensearch's dependencies:
- **dream_http_client** - HTTP client (built on gun)
- **Gleam stdlib** - Type-safe, battle-tested
- **BEAM/OTP** - 30+ years of production use

We monitor dependencies and update promptly for security issues.

## Questions?

- **Security questions**: engineering@trustbound.ai
- **Non-security issues**: [GitHub Issues](https://github.com/TrustBound/dream_opensearch/issues)
- **General discussion**: [GitHub Discussions](https://github.com/TrustBound/dream/discussions)

---

**Remember:** dream_opensearch is a library. It provides tools. You write the application. You're responsible for your application's security.
