#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_UNDER_TEST="${REPO_ROOT}/cd-bookmarks.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
	local name="$1"
	printf 'PASS: %s\n' "${name}"
	((PASS_COUNT++))
}

fail() {
	local name="$1"
	printf 'FAIL: %s\n' "${name}"
	((FAIL_COUNT++))
}

run_test() {
	local name="$1"
	local fn="$2"

	if ( "${fn}" ); then
		pass "${name}"
	else
		fail "${name}"
	fi
}

source_under_test() {
	# shellcheck disable=SC1091
	# shellcheck source=../cd-bookmarks.sh
	source "${SCRIPT_UNDER_TEST}"
}

test_default_bookmark_file_expands_home() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_includebookmarks cd_usepushd cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1

	[[ "${CD_BOOKMARKS_FILE}" == "${HOME}/.cd_bookmarks" ]]
}

test_preserve_preconfigured_flags() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	cd_includebookmarks=2
	cd_usepushd=0
	source_under_test || return 1

	[[ "${cd_includebookmarks}" == '2' && "${cd_usepushd}" == '0' ]]
}

test_bookmark_index_update_is_idempotent() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1

	declare -A cd_bookmarks=([default]='.' [alpha]='/tmp' [beta]='/var')
	bookmark_index=''
	_cdb_update
	local first="${bookmark_index}"
	_cdb_update
	local second="${bookmark_index}"

	[[ "${first}" == "${second}" ]]
}

test_pushd_can_be_disabled() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1

	declare -A cd_bookmarks=([default]='.')
	cd_usepushd=0
	local before after
	before="$(dirs -p | wc -l)"
	cdb /tmp || return 1
	after="$(dirs -p | wc -l)"

	[[ "${before}" == "${after}" ]]
}

test_failed_cd_does_not_mutate_directory_stack() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1

	declare -A cd_bookmarks=([default]='.')
	cd_usepushd=1
	local missing="/definitely/not/a/real/path-${RANDOM}-${RANDOM}"
	local before after
	before="$(dirs -p | wc -l)"
	if cdb "${missing}" >/dev/null 2>&1; then
		return 1
	fi
	after="$(dirs -p | wc -l)"

	[[ "${before}" == "${after}" ]]
}

test_explicit_bookmark_flag_wins_over_subdir_name_collision() {
	local temp_home base
	temp_home="$(mktemp -d)" || return 1
	base="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS

	mkdir -p "${base}/work/docs" "${base}/other/docs" || return 1
	source_under_test || return 1

	declare -A cd_bookmarks=([default]='.' [work]="${base}/work" [docs]="${base}/other")
	cd "${base}" || return 1
	cdb docs -b work >/dev/null 2>&1 || return 1

	[[ "${PWD}" == "${base}/work/docs" ]]
}

test_cdb_save_persists_cd_bookmarks_map() {
	local temp_home save_file
	temp_home="$(mktemp -d)" || return 1
	save_file="$(mktemp)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1
	CD_BOOKMARKS_FILE="${save_file}"
	declare -A cd_bookmarks=([default]='.')

	cdb --save work /tmp || return 1

	[[ -f "${save_file}" ]] || return 1
	[[ "$(sed -n '1p' "${save_file}")" == 'declare -A cd_bookmarks=(' ]] || return 1

	unset cd_bookmarks
	# shellcheck disable=SC1090
	source "${save_file}" || return 1
	[[ "${cd_bookmarks[work]}" == '/tmp' ]]
}

test_cdb_mem_mode_is_session_only() {
	local temp_home save_file
	temp_home="$(mktemp -d)" || return 1
	save_file="$(mktemp)" || return 1
	rm -f -- "${save_file}" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1
	CD_BOOKMARKS_FILE="${save_file}"
	declare -A cd_bookmarks=([default]='.')

	cdb --mem one /tmp || return 1
	[[ ! -e "${save_file}" ]] || return 1
	cdb --save two /tmp || return 1
	[[ -f "${save_file}" ]] || return 1

	unset cd_bookmarks
	# shellcheck disable=SC1090
	source "${save_file}" || return 1
	[[ "${cd_bookmarks[one]-}" == '' ]] || return 1
	[[ "${cd_bookmarks[two]}" == '/tmp' ]]
}

test_cdb_save_without_path_uses_pwd() {
	local temp_home save_file target_dir
	temp_home="$(mktemp -d)" || return 1
	save_file="$(mktemp)" || return 1
	target_dir="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1
	CD_BOOKMARKS_FILE="${save_file}"
	declare -A cd_bookmarks=([default]='.')

	builtin cd "${target_dir}" || return 1
	cdb --save current || return 1

	unset cd_bookmarks
	# shellcheck disable=SC1090
	source "${save_file}" || return 1
	[[ "${cd_bookmarks[current]}" == "${target_dir}" ]]
}

test_bookmark_cd_rejects_missing_directory() {
	local temp_home
	temp_home="$(mktemp -d)" || return 1
	HOME="${temp_home}"
	unset CD_BOOKMARKS_FILE cd_bookmarks CD_BOOKMARKS
	source_under_test || return 1
	declare -A cd_bookmarks=([default]='.')

	if bookmark_cd bad "/does/not/exist-${RANDOM}-${RANDOM}" >/dev/null 2>&1; then
		return 1
	fi
	return 0
}

main() {
	run_test 'default bookmark file expands home' test_default_bookmark_file_expands_home
	run_test 'preconfigured flags are preserved' test_preserve_preconfigured_flags
	run_test 'bookmark index update is idempotent' test_bookmark_index_update_is_idempotent
	run_test 'pushd can be disabled' test_pushd_can_be_disabled
	run_test 'failed cd does not mutate stack' test_failed_cd_does_not_mutate_directory_stack
	run_test 'explicit -b wins over name collision' test_explicit_bookmark_flag_wins_over_subdir_name_collision
	run_test 'cdb --save persists cd_bookmarks map' test_cdb_save_persists_cd_bookmarks_map
	run_test 'cdb --mem mode is session only' test_cdb_mem_mode_is_session_only
	run_test 'cdb --save without path uses current directory' test_cdb_save_without_path_uses_pwd
	run_test 'bookmark_cd rejects missing directories' test_bookmark_cd_rejects_missing_directory

	printf '\nSummary: %s passed, %s failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"
	[[ "${FAIL_COUNT}" -eq 0 ]]
}

main "$@"
