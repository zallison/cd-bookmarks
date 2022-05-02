#!/bin/bash

# Copyright 2022, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
# optionally enabling pushd when changing directories.

function _cdb_help {
    \cd --help
    echo
    echo '    CD-BOOKMARKS.sh:
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
        cd -update # re-index the bookmarks

    After updating bookmarks run `cd -update`

    The default "bookmark" is ".", but you can change that if you want.
        cd_bookmarks["default"]=".:${HOME}/projects/

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
"'
}



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
declare -A cd_bookmarks
cd_bookmarks["default"]="."

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
            "-update") _cdb_update; return;;
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

    ## Determine path to cd to
    local tmpcdpath=${cd_bookmarks[${bookmark:-default}]}
    if [[ -z "$bookmark" && -z "$directory" ]]; then
        :
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

    ## if `pushd` is enabled add PWD when changing directories.
    # Q: why not just pushd instead of cd?
    # A: to respect all the flags to cd like -L or -P
    if [[ ${cd_usepushd} ]]; then
        if [[ "$OLDPWD" != "$PWD" && "$PWD" != "$directory" ]]; then
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
    # Unless we see a bookmark, we're using the default path list
    tmpcdpath=${cd_bookmarks["default"]}

    # No space for completion (for directories and subdirectories)
    compopt -o nospace

    if [[ -n "$prev" && "$prev" != "cdb" && "$prev" != "cd" ]]; then
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
    if [[ "$cd_includebookmarks" ]]; then
        if [[ "$cd_includebookmarks" == "2" ]]; then
            compopt +onospace
            if [[ "z$prev" == "zcd" || "z$prev" == "zcdb" ]]; then
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
