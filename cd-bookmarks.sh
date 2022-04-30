#!/bin/bash
#
# Copyright 2020, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality.

declare -A cd_bookmarks
declare cd_includebookmarks=0 # include bookmarks in tab completion for directories

cd_bookmarks["default"]="."

# Replace "cd" with "bcd"
alias cd=bcd
complete -F _bcd cd

function bcd {
    local cdopts
    local bookmark
    local directory

    while [[ "$1" ]]; do
        case "$1" in
            "-") \cd ${OLDPWD}; return;;
            "-b") if [[ $2 ]]; then
                      bookmark=$2; shift;
                  else
                      _bcd_show_list; return 0
                  fi;;
            "--help") _bcd_help; return;;
            -*) cdopts+=" $1";;
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

    local tmpcdpath=${cd_bookmarks[${bookmark:-default}]}
    ## Determine path to cd to
    if [[ -z "$bookmark" && -z "$directory" ]]; then
        \cd ${cdopts}
    elif [[ -n "$bookmark" && -z "$directory" ]]; then
        # Bookmark, but no directory,
        if [[ -n "$bookmark" && -z "${cd_bookmarks[$bookmark]}" ]]; then
            echo "Unknown bookmark: $bookmark"; return 1;
        fi
        directory="${cd_bookmarks[$bookmark]}"
        bookmark=default
    elif [[ -z "$bookmark" && -n $directory && -n "${cd_bookmarks[$directory]}" ]]; then
        directory="${cd_bookmarks[$directory]}"
        tmpcdpath=
    elif [[ -n "$bookmark" && -d "${cd_bookmarks[$directory]}" ]]; then
        directory="${cd_bookmarks[$directory]}"
        tmpcdpath=
    fi

    CDPATH="${tmpcdpath}" \cd ${cdopts} "$directory" || return 1
}


complete -F _bcd bcd
function _bcd {
    local curr prev words cword tmpcdpath TMP
    curr="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    # Unless we see a bookmark, we're using the default path list
    tmpcdpath=${cd_bookmarks["default"]}

    # No space for completion (for directories and subdirectories)
    compopt -o nospace

    if [[ -n "$prev" && "$prev" != "bcd" && "$prev" != "cd" ]]; then
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
    CDPATH=$tmpcdpath _bcd_comp "$*"

    # Add in the bookmarks
    if [[ "$cd_includebookmarks" ]]; then
        if [[ "$cd_includebookmarks" == "2" ]]; then
            compopt +onospace
            if [[ "z$prev" == "zcd" || "z$prev" == "zbcd" ]]; then
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
function _bcd_comp {
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

function _bcd_help {
    \cd --help
    echo
    echo '    CD-BOOKMARKS.sh:
    This script has added the ability to use bookmarks to cd.
    Examples:
        cd -b  # list bookmarks
        cd [-b] bookmark # cd to a bookmark
        cd [-b] bookmark subdir # cd to a directory below a bookmark

    Set your bookmarks, in .bashrc or elsewhere:
        cd_bookmarks["name"]="/path/to/bookmark"
        cd_bookmarks["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"
        cd-bookmarks  -update

    After updating bookmarks run `cd-bookmarks-update`

    The default "bookmark" is ".", but you can change that if you want.
        cd_bookmarks["default"]=".:${HOME}/projects/"'
}

function _bcd_show_list {
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

function cd-bookmarks-update() {
    for i in "${!cd_bookmarks[@]}"; do
        if [[ $i != "default" ]]; then
            bookmark_index="$i ${bookmark_index}"
        fi
    done
}
