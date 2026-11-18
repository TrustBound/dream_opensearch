# dream_opensearch Makefile

.PHONY: test build format check docs clean

# Run the tests with the coverage report (fails below 100% coverage)
test:
	@gleam test

# Build the package
build:
	@gleam build

# Format the code
format:
	@gleam format src test

# Format check, build, tests and docs build (the CI checks)
check:
	@gleam format --check src test
	@gleam build
	@gleam test
	@gleam docs build

# Generate the documentation
docs:
	@gleam docs build

# Remove build artifacts
clean:
	@gleam clean
	@rm -f erl_crash.dump
