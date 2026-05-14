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

# === DOCUMENTATION ===

# Build documentation
docs:
    gleam docs build

# Generate website reference docs from Gleam docs JSON
site-reference: docs
    cd website && pnpm generate:reference

# Install website dependencies
site-deps:
    cd website && pnpm install

# Build website
site-build: site-reference
    cd website && pnpm build:site

# Type-check and validate website
site-check: site-reference
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
change:
    changie new

# Preview unreleased changelog
changelog-preview:
    changie batch auto --dry-run

# Generate CHANGELOG.md
changelog:
    changie merge

# === MAINTENANCE ===

# Remove build artifacts
clean:
    rm -rf build

# === CI ===

# Run all CI checks (format, check, test, build)
ci: format-check check test build-strict

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs site-check site-build
