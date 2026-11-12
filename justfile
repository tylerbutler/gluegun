# Gleam Project Tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias d := docs
alias sd := site-deps
alias sb := site-build
alias sc := site-check
alias cl := change
alias td := trellis-doctor
alias eb := examples-build
alias ef := examples-format
alias efc := examples-format-check

default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    gleam deps download

# === BUILD ===

# Build project (Erlang target)
build:
    gleam build

# Build with warnings as errors
build-strict:
    gleam build --warnings-as-errors

# === TESTING ===

# Run all tests
test:
    gleam test

# Check release preparation without GitHub writes or release commands
test-release:
    python3 -B -m unittest discover -s test -p release_pr_test.py

# === CODE QUALITY ===

# Format source code
format:
    gleam format src test

# Check formatting without changes
format-check:
    gleam format --check src test

# Type check without building
check:
    gleam check

# === EXAMPLES ===

# Download dependencies for every standalone example package
examples-deps:
    trellis run examples-deps --serial

# Format every standalone example package
examples-format:
    trellis run examples-format

# Check formatting for every standalone example package
examples-format-check:
    trellis run examples-format-check

# Run tests for standalone example packages with test directories
examples-test:
    trellis run examples-test --serial

# Build examples serially to avoid concurrent Hex cache writes; also package escripts
examples-build:
    trellis run examples-build --serial

# === DOCUMENTATION ===

# Build documentation
docs:
    gleam docs build

# Compile complete README/website examples and check owned HTTP cleanup
docs-examples:
    python3 -B scripts/check_documentation_examples.py

# Generate website reference docs from Gleam docs JSON
site-reference:
    cd website && pnpm generate:reference

# Compare committed reference pages with current Gleam metadata
site-reference-check:
    cd website && pnpm check:reference

# Install website dependencies
site-deps:
    cd website && pnpm install

# Build website
site-build:
    cd website && pnpm build

# Type-check and validate website
site-check:
    cd website && pnpm check:astro

# Start local website dev server
site-dev:
    cd website && pnpm dev

# Preview built website
site-preview:
    cd website && pnpm preview

# Remove website build artifacts
site-clean:
    cd website && pnpm clean

# === CHANGELOG ===

# Create a new changelog entry
change *ARGS:
    trellis changelog new {{ARGS}}

# Preview unreleased changelog
changelog-preview *ARGS:
    trellis version plan {{ARGS}}

# Apply pending versions and regenerate CHANGELOG.md
changelog *ARGS:
    trellis version apply {{ARGS}}

# Validate the Trellis workspace
trellis-doctor:
    trellis doctor

# === MAINTENANCE ===

# Remove build artifacts
clean:
    rm -rf build

# === CI ===

# Run all CI checks (format, check, test, build, workspace)
ci: format-check check test test-release examples-format-check examples-test docs-examples build-strict trellis-doctor

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci examples-build docs site-reference-check site-check site-build
