# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Added a standalone regression test suite at `tests/regression.sh`.
- Added regression coverage for bookmark persistence, explicit `-b` resolution, pushd stack behavior, config defaults, and index update idempotency.

### Changed
- Changed persistent bookmark file handling to use `CD_BOOKMARKS_FILE` consistently.
- Changed bookmark save behavior to use atomic writes through a temporary file before replace.
- Changed `cdb` option parsing and internal handling to be safe under `set -u` / nounset.
- Changed completion handling to use safer array and `mapfile` patterns.
- Improved bookmark list formatting and bookmark index rebuild behavior.

### Fixed
- Fixed default bookmark file expansion so `$HOME` resolves correctly.
- Fixed stale `--save` state leaking across calls to `bookmark_cd`.
- Fixed explicit bookmark targeting (`-b`) being overridden by colliding bookmark names.
- Fixed pushd history updates occurring on failed `cd` attempts.
- Fixed duplicate bookmark completion index growth after repeated `--update`.
- Fixed README variable and bookmark-map name mismatches (`CD_BOOKMARKS_FILE`, `cd_bookmarks`).

### Documentation
- Added regression test instructions to `README.md`.
