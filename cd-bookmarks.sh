#!/bin/bash
#
# Copyright 2020, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality.

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
        CD_BOOKMARKS["name"]="/path/to/bookmark"
        CD_BOOKMARKS["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"
        cd-bookmarks-update

    After updating bookmarks run `cd-bookmarks-update`

    The default "bookmark" is ".", but you can change that if you want.
        CD_BOOKMARKS["default"]=".:${HOME}/projects/"'

}


declare -A CD_BOOKMARKS
declare CD_INCLUDEBOOKMARKS=0 # include bookmarks in tab completion for directories

CD_BOOKMARKS["default"]="."

# Replace "cd" with "bcd"
alias cd=bcd
complete -F _bcd cd

function bcd {
    local CDOPTS

    while [[ "$1" == "-"[^b]* ]]; do
        if [[ "$1" == "--help" ]]; then
            _bcd_help
            return
        fi
        CDOPTS+=" $1"
        shift
    done

    if [[ -z "$1" ]]; then
        # No arguments
        \cd ${CDOPTS}
        return
    elif [[ "$1" == "-b" && -z "$2" ]]; then
        # only -b
        _bcd_show_list
        return
    fi

    # Pop off the -b, leaving a directory and maybe a bookmark
    if [[ "$1" == "-b" ]]; then shift; fi

    if [[ ! -z "$3" ]]; then
        echo "Too many arguments"
        return 1
    elif [[ ! -z "$2" && -z "${CD_BOOKMARKS[$1]}"  ]]; then
        echo "Unknown bookmark: $1"
        return 1
    elif [[ ! -z "$2" ]]; then
        # Two args: bookmark subdir
        CDPATH=${CD_BOOKMARKS[$1]} \cd ${CDOPTS} "$2"
    elif [[ ! -z $1 && ! -d "$1" && ! -z "${CD_BOOKMARKS[$1]}" ]]; then
        # One arg that is a bookmark
        \cd ${CDOPTS} ${CD_BOOKMARKS[$1]%%:*}
    else
        # One arg  use the default search path.
        CDPATH=${CD_BOOKMARKS["default"]} \cd ${CDOPTS} "$1"
    fi
}


complete -F _bcd bcd
function _bcd {
    local curr prev words cword TMPCDPATH TMP
    curr="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    # Unless we see a bookmark, we're using the default path list
    TMPCDPATH=${CD_BOOKMARKS["default"]}

    # Add spaces to the end of words
    compopt -o nospace

    if [[ ! -z "$prev" && "$prev" != "bcd" && "$prev" != "cd" ]]; then
        TMP=${CD_BOOKMARKS["$prev"]}
        if [[ ! -z "$TMP" ]]; then
            TMPCDPATH=${CD_BOOKMARKS[$prev]}
        fi
    fi

    if [[ "$prev" == "-b" ]]; then
        compopt +o nospace
        COMPREPLY=($(compgen -W "${BOOKMARK_INDEX}" -- "$curr") )
        return
    elif [[ "$curr" == "-"* ]]; then
        compopt +o nospace
        COMPREPLY=($(compgen -W "- -L -P -e -@ --help -b" -- "$curr") )
        return
    fi

    # "Normal" cd completion with CDPATH set
    CDPATH=$TMPCDPATH _bcd_comp "$*"

    # Add in the bookmarks
    if [[ "$prev" &&  ! "${CD_BOOKMARKS[$prev]}" && "$CD_INCLUDEBOOKMARKS" == "1" ]]; then
        COMPREPLY+=($(compgen -W "${BOOKMARK_INDEX}" -- "$curr") )
    fi
}

# Based on the built in _cd
function _bcd_comp {
    local cur prev i j k
    _init_completion || return;
    local IFS='
'
    compopt +o filenames -o nospace;

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

function _bcd_show_list {
    function _add_x_spaces {
        for x in $(seq 1 $(( $1 )) ); do echo -n " "; done
    }
    echo "Bookmarks:"
    local maxlength tmp="[default]"
    maxlength=${#tmp}
    for i in "${!CD_BOOKMARKS[@]}"; do
        [[ ${#i} -gt ${maxlength} ]] && maxlength=${#i}
    done
    echo "  [default] -> ${CD_BOOKMARKS[default]}"
    for i in "${!CD_BOOKMARKS[@]}"; do
        if [[ $i != "default" ]]; then
            echo -n "  $i "
            _add_x_spaces $(( ${maxlength} - ${#i} ))
            echo -e "-> ${CD_BOOKMARKS[$i]}"
        fi
    done
}

function cd-bookmarks-update() {
    for i in "${!CD_BOOKMARKS[@]}"; do
        if [[ $i != "default" ]]; then
            BOOKMARK_INDEX="$i ${BOOKMARK_INDEX}"
        fi
    done
}
