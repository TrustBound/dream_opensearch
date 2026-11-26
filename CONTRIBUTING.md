# Contributing to dream_opensearch

Thank you for your interest in contributing to dream_opensearch! We're excited to have you here.

dream_opensearch is part of the [Dream](https://github.com/TrustBound/dream) family. It follows Dream's coding and testing standards.

## Quick Links

📖 **[Full Contributing Guide](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/contributing/contributing.md)** - Detailed contribution guidelines  
🧪 **[Testing Guide](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/contributing/testing.md)** - Testing standards  
🤝 **[Code of Conduct](CODE_OF_CONDUCT.md)** - Community standards  
🔒 **[Security Policy](SECURITY.md)** - Reporting security vulnerabilities

## Set up dream_errors, which is not on Hex yet

dream_opensearch needs dream_errors 1.0.0, and dream_errors is not on Hex yet. Until it is, `gleam deps download` fails, and CI fails at that step. To build on your computer:

1. Clone [dream_errors](https://github.com/TrustBound/dream_errors) next to this repository.
2. Copy its `src` folder and its `gleam.toml` into `build/packages/dream_errors`.
3. Add the line `dream_errors = "1.0.0"` under `[packages]` in `build/packages/packages.toml`.

`manifest.toml` lists dream_errors with a checksum of zeros. When dream_errors is on Hex, remove this section and run `gleam deps update dream_errors` to write the real checksum.

## Quick Start for Contributors

### Prerequisites

- Gleam 1.19.2 or later
- Erlang/OTP 28 (the coverage report needs OTP 27 or later with the JIT)
- rebar3

### Development Setup

1. **Fork and clone:**
   ```bash
   git clone https://github.com/YOUR-USERNAME/dream_opensearch.git
   cd dream_opensearch
   ```

2. **Run tests:**
   ```bash
   make search-up           # Start OpenSearch 2.19.1 in Docker, wait until healthy
   make test                # All tests, with the coverage report
   make search-down         # Stop OpenSearch
   ```

   The tests run against a real OpenSearch from `docker-compose.yml`, on
   ports 9201 and 9202. Set `OPENSEARCH_URL` and `OPENSEARCH_SECURED_URL`
   to use other nodes. A few failure tests use a small local server on
   127.0.0.1.

   The round trip through a `dream_http_client` recorder plays back the
   recordings in `test/recordings/`, with no cluster. To record them
   again, run `RECORD_OPENSEARCH=true make test` with the OpenSearch of
   `make search-up` running.

3. **Make your changes:**
   - Write code following Dream's [design principles](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/reference/design-principles.md)
   - Add tests for new functionality
   - Update documentation as needed

4. **Format and verify:**
   ```bash
   gleam format             # Format code
   make check               # Format check, build, tests and docs build
   ```

5. **Submit a pull request:**
   - Clear description of changes
   - Reference any related issues
   - Ensure CI passes

## What Can I Contribute?

### 🐛 Bug Reports
Found a bug? [Open an issue](https://github.com/TrustBound/dream_opensearch/issues/new) with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Your environment (Gleam version, OS, OpenSearch version, etc.)

### 💡 Feature Requests
Have an idea? [Open an issue](https://github.com/TrustBound/dream_opensearch/issues/new) with:
- Clear use case
- Proposed API or behavior
- Why this fits Dream's philosophy

### 📝 Documentation
Documentation improvements are always welcome:
- Fix typos or unclear explanations
- Add examples
- Improve guides

### 🔧 Code Contributions
- Fix bugs
- Implement approved features
- Improve performance
- Add tests

## Code Standards

dream_opensearch follows Dream's strict coding standards. Please read:
- **[Design Principles](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/reference/design-principles.md)** - The "why" behind Dream
- **[Naming Conventions](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/reference/naming-conventions.md)** - Code style rules

Key principles:
- **No magic** - Everything explicit
- **No closures** - All dependencies are parameters
- **Full words** - No abbreviations (except standard ones)
- **100% test coverage** - For `src/` code; `gleam test` fails below 100%
- **Black box testing** - Test public interfaces only

## Development Workflow

1. **Create a branch:**
   ```bash
   git checkout -b feature/my-feature
   # or
   git checkout -b fix/issue-123
   ```

2. **Make focused commits:**
   ```bash
   git commit -m "Add scroll search"
   ```

3. **Keep your fork updated:**
   ```bash
   git remote add upstream https://github.com/TrustBound/dream_opensearch.git
   git fetch upstream
   git rebase upstream/main
   ```

4. **Push and create PR:**
   ```bash
   git push origin feature/my-feature
   ```

## Testing Requirements

All contributions must include tests:

- **Unit tests** - Fast, isolated, deterministic
- **100% coverage** - For the code in `src/`
- **Tested snippets** - Every Gleam code block in the docs comes from a file in `test/snippets/` that the tests run

See the [Testing Guide](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/contributing/testing.md) for details.

## Documentation Requirements

Update documentation for:
- New features (HexDocs + README)
- API changes (update all references)
- Breaking changes (migration notes in CHANGELOG.md)

## Review Process

1. **Automated checks:**
   - Code formatting (`gleam format`)
   - Unit tests with 100% coverage
   - Documentation build
   - No compiler warnings

2. **Manual review:**
   - Code quality
   - Tests coverage
   - Documentation
   - Fits Dream's philosophy

3. **Maintainer approval:**
   - At least one maintainer approval required
   - May request changes or clarification

## Getting Help

- **Questions?** [Open a discussion](https://github.com/TrustBound/dream/discussions)
- **Stuck?** Comment on your PR or issue
- **Security issue?** See [SECURITY.md](SECURITY.md)

## Recognition

All contributors are recognized in our documentation and release notes. Thank you for making dream_opensearch better! 🎉

## About Dream

Dream was created by [TrustBound](https://trustbound.ai), an AI security platform, to build our production SaaS. We needed a type-safe web toolkit that was explicit, composable, and ran on the BEAM for massive concurrency.

We built Dream, used it to build TrustBound, and open-sourced it under MIT license so others could benefit.

Dream is community-driven. TrustBound funds development, but contributions come from everyone. All decisions happen in public issues and discussions.

---

**Read more:** [Full Contributing Guide](https://github.com/TrustBound/dream/blob/release/3.0.0/docs/contributing/contributing.md)
