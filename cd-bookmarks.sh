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



## include bookmarks in tab completion for directories
declare cd_includebookmarks=0

## enable pushd when changing directories
# Q: why not pushd the target dir like a normal person?
# A: because then the rest of the cd flags like -L or -P aren't respected
declare cd_usepushd=1;

# cd [...] will add PWD with pushd before changing direction
# cd -v will run dirs -v
# cd -p will run popd

## Create default bookmark
# set CDPATH to "."
if [[ -z ${cd_bookmarks} ]]; then
    declare -A cd_bookmarks
    cd_bookmarks["default"]="."
fi

## Alias and complete
# Replace "cd" with "cdb"
alias cd=cdb
complete -F _cdb cd

function cdb {
    local cdopts
    local bookmark
    local directory

    while [[ "$1" ]]; do
        case "$1" in
            "-p") popd; return;;
            "-v") dirs -v; return;;
            "-b") if [[ $2 ]]; then
                      bookmark=$2; shift;
                  else
                      _cdb_show_list; return 0
                  fi;;
            "--help") _cdb_help; return;;
            "--update") _cdb_update; return;;
            -[A-Za-z]) cdopts+=" $1";;
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

    # Remove trailing slashes to check for hash
    # e.g.: my_bookmark/ -> my_bookmark
    directory=${directory%%/}

    ## Determine path to cd to
    local tmpcdpath=${cd_bookmarks[${bookmark:-default}]}
    if [[ -z "$bookmark" && -z "$directory" ]]; then
        :
    elif [[ -z "$bookmark" &&  -n "$directory" && -d "$directory" ]]; then
        # A directory, no bookmark, and the directory exists as a full path
        tmpcdpath=.

    elif [[ -n "$bookmark" && -z "$directory" ]]; then
        # Bookmark, but no directory,
        if [[ -n "$bookmark" && -z "${cd_bookmarks[$bookmark]}" ]]; then
            echo "Unknown bookmark: $bookmark"; return 1;
        fi
        directory="${cd_bookmarks[$bookmark]}"
        bookmark=default

    elif [[ -z "$bookmark" && -n "$directory" && -n "${cd_bookmarks[$directory]}" ]]; then
        # "Directory" which is a bookmark
        directory="${cd_bookmarks[$directory]}"
        tmpcdpath=

    elif [[ -n "$bookmark" && -d "${cd_bookmarks[$directory]}" ]]; then
        directory="${cd_bookmarks[$directory]}"
        tmpcdpath=
    fi

    if [[ -z "$bookmark" && ! -z "$directory" ]]; then
        first_dir=${directory%/*}
        first_dir=${first_dir%%/*}
        if [[ -n "$first_dir" && ! -z ${cd_bookmarks[${first_dir}]} ]]; then
            bookmark=${first_dir}
            directory=${directory#*/}
            tmpcdpath=${cd_bookmarks[$bookmark]}
        fi
    fi

    ###############
    ## if `pushd` is enabled add PWD when changing directories.
    # Q: why not just pushd instead of cd?
    # A: to respect all the flags to cd like -L or -P
    if [[ ${cd_usepushd} ]]; then
       if [[ "$OLDPWD" != "$PWD" ]]; then
            pushd . 2>&1 > /dev/null
       fi
    fi

    if [[ "$directory" == "-" ]]; then
        command cd ${cdopts} - || return 1
    elif [[ -z "$bookmark" && -z "$directory" ]]; then
        command cd ${cdopts} || return 1
    else
        CDPATH="${tmpcdpath}" command cd ${cdopts} "$directory" || return 1
    fi
}


complete -F _cdb cdb
function _cdb {
    local curr prev words cword tmpcdpath TMP
    curr="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    word_count=${#COMP_WORDS[@]}
    # Unless we see a bookmark, we're using the default path list
    tmpcdpath=${cd_bookmarks["default"]}

    # No space for completion (for directories and subdirectories)
    compopt -o nospace

    if [[ -n "$prev" && ${word_count} > 1 ]]; then
        TMP="${cd_bookmarks["$prev"]}"
        if [[ -n "$TMP" ]]; then
            tmpcdpath="$TMP"
        fi
    fi

    if [[ "$prev" == "-b" ]]; then
        # Return bookmarks
        compopt +o nospace
        COMPREPLY=($(compgen -W "${bookmark_index}" -- "$curr") )
        return

    elif [[ "$curr" == "-"* ]]; then
        # Return options
        compopt +o nospace
        COMPREPLY=($(compgen -W "- -L -P -e -@ --help -b" -- "$curr") )
        return

    elif [[ "$curr" && ${cd_bookmarks["$curr"]} ]]; then
        compopt +o nospace
        COMPREPLY=($curr)
        return
    fi

    # "Normal" cd completion with CDPATH set
    CDPATH=$tmpcdpath _cdb_comp "$*"

    # Add in the bookmarks
    if [[ "$cd_includebookmarks" && "${word_count}" == 2 ]]; then
        if [[ "$cd_includebookmarks" == "2" ]]; then
            compopt +onospace
            if [[ "${word_count}" > 1 ]]; then
                COMPREPLY=()
            fi
        fi

        COMPREPLY+=($(compgen -W "${bookmark_index}" -- "$curr") )

        if [[ ${#COMPREPLY[@]} -eq 1 && "${cd_bookmarks[${COMPREPLY[0]}]}" ]]; then
            # Add a space after completing a bookmark
            compopt +onospace
        fi
    fi
}

# Based on the built in _cd
function _cdb_comp {
    local cur prev i j k
    _init_completion || return 1;
    local IFS='
'
    compopt -o filenames -o nospace;

    if [[ -z "${CDPATH:-}" || "$cur" == ?(.)?(.)/* ]]; then
        _filedir -d
        return
    fi

    local -r mark_dirs=$(_rl_enabled mark-directories && echo y)
    local -r mark_symdirs=$(_rl_enabled mark-symlinked-directories && echo y)

    for i in ${CDPATH//:/'
'};
    do
        k="${#COMPREPLY[@]}";
        for j in $( compgen -d -- "$i"/"$cur" );
        do
            if [[ ( -n $mark_symdirs && -h $j || -n $mark_dirs && ! -h $j ) && ! -d ${j#$i/} ]]; then
                j+="/"
            fi
            COMPREPLY[k++]=${j#$i/};
        done
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
    function _add_x_spaces {
        for _ in $(seq 1 $(( $1 )) ); do echo -n " "; done
    }
    echo "Bookmarks:"
    local maxlength tmp="[default]"
    maxlength=${#tmp}
    for i in "${!cd_bookmarks[@]}"; do
        [[ ${#i} -gt ${maxlength} ]] && maxlength=${#i}
    done
    echo "  [default] -> ${cd_bookmarks[default]}"
    for i in "${!cd_bookmarks[@]}"; do
        if [[ $i != "default" ]]; then
            echo -n "  $i "
            _add_x_spaces $(( ${maxlength} - ${#i} ))
            echo -e "-> ${cd_bookmarks[$i]}"
        fi
    done
}

function _cdb_update() {
    for i in "${!cd_bookmarks[@]}"; do
        if [[ $i != "default" ]]; then
            bookmark_index="$i ${bookmark_index}"
        fi
    done
}
