#!/bin/bash

# Copyright 2022, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
# optionally enabling pushd when changing directories.
CD_BOOKMARK_FILE=${CD_BOOKMARK_FILE:-"~/.cd_bookmarks"}

cd_includebookmarks=1
cd_usepushd=1

[[ -f "${CD_BOOKMARK_FILE}" ]] && source "${CD_BOOKMARK_FILE}"

bookmark_cd() {
    cd_bookmarks_temporary="mark"
    if [[ $1 == "-s" || $1 == "--save" ]]; then
        save=1
        shift
    fi

    bookmark=${1:-mark}
    dir=$2

    # Validate
    [[ "$dir" ]] || dir=$(pwd)

    # Not a directory
    if [[ ! -d "$dir" ]]; then
        echo "$dir is not a directory" > /dev/stderr
        return -1
    fi

    # Set the bookmark for the session
    cd_bookmarks["$bookmark"]="$dir"

    if [[ "$save" == 1 ]]; then

        # Invalid bookmark name
        if [[ ${bookmark} == "${cd_bookmarks_temporary}" ]]; then
            echo  "error: Can't save a bookmark to the default slot [${cd_bookmarks_temporary}" > /dev/stderr
            echo "        \$cd_bookmarks_temporary is set at the top of this function" > /dev/stderr
            return -1
        fi

        # Create bookmark file
        if [[ ! -f "${CD_BOOKMARK_FILE}" ]]; then
            > "${CD_BOOKMARK_FILE}" << EOF
## CD BOOKMARKS
## END OF BOOKMARKS
## UPDATE
cd --update
## EOF

EOF
        fi

        NEW='cd_bookmarks["$bookmark"]="'$dir'"'
        echo Writing "$NEW" to $CD_BOOKMARK_FILE
        if [[ $(awk "/.. END OF BOOKMARKS$/{print \"$NEW\"} //{print} " < "$CD_BOOKMARK_FILE" > "${CD_BOOKMARK_FILE}.tmp") ]]; then
            mv "${CD_BOOKMARK_FILE}.tmp" "${CD_BOOKMARK_FILE}"
        else
            echo Error, not clobing old ${CD_BOOKMARK_FILE}
        fi
    fi

    cd --update
}



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
        cd --update # re-index the bookmarks

    After updating bookmarks run `cd --update`

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
