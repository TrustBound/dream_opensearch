# dream_opensearch Makefile

.PHONY: test build format check check-snippets docs clean search-up search-down

# Run the tests with the coverage report (fails below 100% coverage).
# The tests need the OpenSearch of docker-compose.yml: run `make search-up`
# first. Without it, the run stops at once and says how to start it.
test:
	@gleam test

# Start OpenSearch 2.19.1 for the tests (docker-compose.yml) and wait until
# both nodes are healthy: http://localhost:9201 (security plugin off) and
# http://localhost:9202 (security plugin on)
search-up:
	@sh scripts/search-up.sh

# Stop OpenSearch and remove its containers (no data is kept)
search-down:
	@docker compose down

# Build the package
build:
	@gleam build

# Format the code
format:
	@gleam format src test

# Format check, build, tests, docs build and snippet check (what CI runs)
check:
	@sh scripts/check.sh

# Check that each code block in the docs matches a tested snippet
check-snippets:
	@gleam run -m dream_snippets

# Generate the documentation
docs:
	@gleam docs build

# Remove build artifacts
clean:
	@gleam clean
	@rm -f erl_crash.dump
