#!/bin/bash

# Copyright 2022, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
# optionally enabling pushd when changing directories.
CD_BOOKMARKS_FILE=${CD_BOOKMARKS_FILE:-"${HOME}/.cd_bookmarks"}

# Allow users to pre-set these before sourcing.
: "${cd_includebookmarks:=0}"
: "${cd_usepushd:=1}"

if [[ -f "${CD_BOOKMARKS_FILE}" ]]; then
	# Keep shell usable even if persisted bookmark file is malformed.
	# shellcheck disable=SC1090
	if ! source "${CD_BOOKMARKS_FILE}"; then
		echo "warning: Failed to load ${CD_BOOKMARKS_FILE}" > /dev/stderr
	fi
fi

# Backwards compatibility for old persisted files using uppercase variable name.
if [[ -n ${CD_BOOKMARKS+x} ]]; then
	if [[ "$(declare -p CD_BOOKMARKS 2>/dev/null)" == "declare -A"* ]]; then
		declare -gA cd_bookmarks
		for key in "${!CD_BOOKMARKS[@]}"; do
			cd_bookmarks["$key"]="${CD_BOOKMARKS[$key]}"
		done
	fi
fi

# Always ensure the runtime map exists and has a default bookmark.
if ! declare -p cd_bookmarks >/dev/null 2>&1 || [[ "$(declare -p cd_bookmarks 2>/dev/null)" != "declare -A"* ]]; then
	declare -gA cd_bookmarks=()
fi
: "${cd_bookmarks[default]:=.}"

bookmark_cd() {
	local cd_bookmarks_temporary='mark'
	local bookmark dir
	local save=0
	local tmp_file key

	if [[ "${1-}" == '-s' || "${1-}" == '--save' ]]; then
		save=1
		shift
	fi

	bookmark=${1:-mark}
	dir=${2:-"${PWD}"}

	# Not a directory.
	if [[ ! -d "$dir" ]]; then
		echo "$dir is not a directory" > /dev/stderr
		return 1
	fi

	# Update the bookmark for this shell session.
	cd_bookmarks["$bookmark"]="$dir"

	if [[ "$save" -eq 1 ]]; then
		# Prevent persisting the temporary default slot.
		if [[ ${bookmark} == "${cd_bookmarks_temporary}" ]]; then
			echo "error: Can't save a bookmark to the default slot [${cd_bookmarks_temporary}" > /dev/stderr
			echo "       Choose an explicit bookmark name when using --save" > /dev/stderr
			return 1
		fi

		if ! mkdir -p -- "$(dirname -- "${CD_BOOKMARKS_FILE}")"; then
			echo "error: Failed to create bookmark directory for ${CD_BOOKMARKS_FILE}" > /dev/stderr
			return 1
		fi

		# Write atomically through a temporary file.
		tmp_file="${CD_BOOKMARKS_FILE}.tmp"
		if ! (
			echo 'declare -A cd_bookmarks=('
			for key in "${!cd_bookmarks[@]}"; do
				printf '    [%q]=%q\n' "$key" "${cd_bookmarks[$key]}"
			done
			echo ')'
		) > "${tmp_file}"; then
			echo "error: Failed to write temporary bookmark file ${tmp_file}" > /dev/stderr
			return 1
		fi

		if ! mv -- "${tmp_file}" "${CD_BOOKMARKS_FILE}"; then
			echo "error: Failed to replace ${CD_BOOKMARKS_FILE}" > /dev/stderr
			return 1
		fi
	fi

	_cdb_update
}
alias cd_bookmark=bookmark_cd
alias bookmark=bookmark_cd


function _cdb_help {
	builtin help cd
	echo
	cat <<'EOF'
    CD-BOOKMARKS.sh:
	This script has added the ability to use bookmarks to cd.
	Examples:
		cd -b  # list bookmarks
		cd [-b] bookmark # cd to a bookmark
		cd [-b] bookmark subdir # cd to a directory below a bookmark

	Load cd-bookmarks, in .bashrc or elsewhere:

		source /path/to/cd-bookmarks.sh

	Set your bookmarks, in .bashrc or elsewhere:
		cd_includebookmarks=1 # [optional] include bookmarks in tab completion
							  # 2 means ONLY show bookmarks
		cd_usepushd=1 # [optional] use pushd so we can popd (or cd -p) back
		cd_bookmarks["name"]="/path/to/bookmark" # add a bookmark
		cd_bookmarks["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"
		cd --update # re-index the bookmarks

	After updating bookmark file by hand run `cd --update`

	The default "bookmark" is ".", but you can change that if you want.
		cd_bookmarks["default"]=".:${HOME}/projects"

	You may optionally have it use pushd and add "cd -p" to call popd. These
	let you keep a history of the paths you have been in and return to them.

		cd -p # run "popd"
		cd -v # run "dirs -v"
		cd -c # run "dirs -c"

	e.g.:
	  ~$ cd mydir
	  ~/mydir$ cd /usr/mydir2
	  /usr/mydir2$ cd -p
	  ~/mydir$ cd -p
	  ~$
EOF
}




## Alias and complete
# Replace "cd" with "cdb"
alias cd=cdb
complete -F _cdb cd

function cdb {
	local bookmark=''
	local directory=''
	local tmpcdpath
	local first_dir
	local start_pwd
	local -a cdopts=()

	start_pwd="${PWD}"

	while [[ $# -gt 0 ]]; do
		case "$1" in
			"-p") popd || return 1; return;;
			"-v") dirs -v; return;;
			"-c") dirs -c; return;;
			"-b") if [[ ${2-} ]]; then
					  bookmark=$2; shift;
				  else
					  _cdb_show_list; return 0
				  fi;;
			"--help") _cdb_help; return;;
			"--update") _cdb_update; return;;
			-[A-Za-z]) cdopts+=("$1");;
			*) if [[ -z "$directory" ]]; then
				   directory=$1;
			   elif [[ -z "$bookmark" ]]; then
				   bookmark=$directory
				   directory=$1
			   else
				   echo "Too many arguments"
				   return 1
			   fi;;
		esac
		shift;
	done

	# Remove trailing slash from bookmark token.
	directory=${directory%%/}

	# Determine path list to use for cd resolution.
	tmpcdpath=${cd_bookmarks[${bookmark:-default}]}

	if [[ -n "$bookmark" && -z "${cd_bookmarks[$bookmark]+_}" ]]; then
		echo "Unknown bookmark: $bookmark"; return 1;
	fi

	if [[ -z "$bookmark" && -z "$directory" ]]; then
		:
	elif [[ -z "$bookmark" &&  -n "$directory" && -d "$directory" ]]; then
		# A real directory path was provided directly.
		tmpcdpath=.
	elif [[ -n "$bookmark" && -z "$directory" ]]; then
		# Bookmark only: cd directly to bookmark target.
		directory="${cd_bookmarks[$bookmark]}"
		bookmark=default
	elif [[ -z "$bookmark" && -n "$directory" && -n "${cd_bookmarks[$directory]-}" ]]; then
		# "Directory" token is actually a bookmark name.
		directory="${cd_bookmarks[$directory]}"
		tmpcdpath=
	fi

	# Support path shorthand like bookmark/subdir.
	if [[ -z "$bookmark" && -n "$directory" ]]; then
		first_dir=${directory%%/*}
		if [[ -n "$first_dir" && -n ${cd_bookmarks[${first_dir}]-} ]]; then
			bookmark=${first_dir}
			directory=${directory#*/}
			tmpcdpath=${cd_bookmarks[$bookmark]}
		fi
	fi

	# Change directory first. Only update stack if cd succeeded.
	if [[ "$directory" == "-" ]]; then
		command cd "${cdopts[@]}" - || return 1
	elif [[ -z "$bookmark" && -z "$directory" ]]; then
		command cd "${cdopts[@]}" || return 1
	else
		CDPATH="${tmpcdpath}" command cd "${cdopts[@]}" "$directory" || return 1
	fi

	# Keep pushd/popd history without changing current directory.
	if [[ "${cd_usepushd}" == "1" && "${start_pwd}" != "${PWD}" ]]; then
		pushd -n -- "${start_pwd}" > /dev/null || return 1
	fi
}


complete -F _cdb cdb
function _cdb {
	local curr prev word_count tmpcdpath
	local -a completions=()
	curr="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
	word_count=${#COMP_WORDS[@]}
	# Unless we see a bookmark, we're using the default path list.
	tmpcdpath=${cd_bookmarks["default"]}

	# No space for completion (for directories and subdirectories).
	compopt -o nospace

	if [[ -n "$prev" && ${word_count} -gt 1 ]]; then
		if [[ -n "${cd_bookmarks["$prev"]-}" ]]; then
			tmpcdpath="${cd_bookmarks["$prev"]}"
		fi
	fi

	if [[ "$prev" == "-b" ]]; then
		# Return bookmarks.
		compopt +o nospace
		mapfile -t COMPREPLY < <(compgen -W "${bookmark_index}" -- "$curr")
		return
	elif [[ "$curr" == "-"* ]]; then
		# Return options.
		compopt +o nospace
		mapfile -t COMPREPLY < <(compgen -W "- -L -P -e -@ --help --update -b -c -p -v" -- "$curr")
		return
	elif [[ "$curr" && ${cd_bookmarks["$curr"]-} ]]; then
		compopt +o nospace
		COMPREPLY=("$curr")
		return
	fi

	# "Normal" cd completion with CDPATH set.
	CDPATH="$tmpcdpath" _cdb_comp "$*"

	# Add in bookmark names for first positional argument.
	if [[ "${cd_includebookmarks}" =~ ^[0-9]+$ && "${cd_includebookmarks}" -ge 1 && "${word_count}" -eq 2 ]]; then
		if [[ "${cd_includebookmarks}" -eq 2 ]]; then
			compopt +o nospace
			if [[ "${word_count}" -gt 1 ]]; then
				COMPREPLY=()
			fi
		fi
		mapfile -t completions < <(compgen -W "${bookmark_index}" -- "$curr")
		COMPREPLY+=("${completions[@]}")

		if [[ ${#COMPREPLY[@]} -eq 1 && "${cd_bookmarks[${COMPREPLY[0]}]-}" ]]; then
			# Add a space after completing a bookmark.
			compopt +o nospace
		fi
	fi
}

# Based on the built in _cd
function _cdb_comp {
	local cur prev i j k
	local IFS
	local -a cdpath_entries
	_init_completion || return 1;
	compopt -o filenames -o nospace;

	if [[ -z "${CDPATH:-}" || "$cur" == ?(.)?(.)/* ]]; then
		_filedir -d
		return
	fi

	local -r mark_dirs=$(_rl_enabled mark-directories && echo y)
	local -r mark_symdirs=$(_rl_enabled mark-symlinked-directories && echo y)
	IFS=':'
	read -r -a cdpath_entries <<< "${CDPATH}"
	for i in "${cdpath_entries[@]}"; do
		k="${#COMPREPLY[@]}";
		while IFS= read -r j; do
			if [[ ( -n $mark_symdirs && -h $j || -n $mark_dirs && ! -h $j ) && ! -d ${j#"$i"/} ]]; then
				j+="/"
			fi
			COMPREPLY[k++]=${j#"$i"/};
		done < <(compgen -d -- "$i"/"$cur")
	done

	if [[ ${#COMPREPLY[@]} -eq 1 ]]; then
		i=${COMPREPLY[0]};
		if [[ "$i" == "$cur" && $i != "*/" ]]; then
			COMPREPLY[0]="${i}/"
		fi
	elif [[ ${#COMPREPLY[@]} -eq 0 ]]; then
		_filedir -d
	fi

	return
}

function _cdb_show_list {
	echo "Bookmarks:"
	local i maxlength tmp="[default]"
	maxlength=${#tmp}
	for i in "${!cd_bookmarks[@]}"; do
		[[ ${#i} -gt ${maxlength} ]] && maxlength=${#i}
	done
	printf "  %-*s -> %s\n" "${maxlength}" "[default]" "${cd_bookmarks[default]}"
	for i in "${!cd_bookmarks[@]}"; do
		if [[ $i != "default" ]]; then
			printf "  %-*s -> %s\n" "${maxlength}" "${i}" "${cd_bookmarks[$i]}"
		fi
	done
}

function _cdb_update() {
	local i
	bookmark_index=
	for i in "${!cd_bookmarks[@]}"; do
		if [[ $i != "default" ]]; then
			bookmark_index="$i ${bookmark_index}"
		fi
	done
}

_cdb_update
