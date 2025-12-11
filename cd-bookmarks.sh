#!/bin/bash

# Copyright 2022-2025, Zack Allison <zack@zackallison.com>
# License: MIT License
#
# cd-bookmarks.sh - bookmarks with cd
#
# This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
# optionally enabling pushd when changing directories.

# Location to read/write bookmarks
CD_BOOKMARK_FILE=${CD_BOOKMARK_FILE:-"$HOME/.cd_bookmarks"}

## Enable pushd?
# Q: why not pushd the target dir like a normal person?
# A: because then the rest of the cd flags like -L or -P aren't respected
# cd [...] will add PWD with pushd before changing direction
# "cd -v" will run "dirs -v"
# "cd -p" will run "popd

# Enable pushd history when set to 1; set to 0 to disable.
declare cd_usepushd=1

# If not given a bookmark, what CDPATH should we use?
# Recommend "." or ".;~/work"
declare cd_default_bookmark="."

# If not given a bookmark name (i.e. "cd -a")
declare cd_default_bookmark_name="mark"

## End of user variables.


## Create default bookmark, if it doesn't exist
if [[ -z ${cd_bookmarks} ]]; then
	declare -A cd_bookmarks
	cd_bookmarks["default"]=${cd_default_bookmark}
fi


   function _cdb_help {
	   # Normal cd help
	   # shellcheck disable=2164
	   \cd --help
	   # Appends our help to the end
	   echo
	   echo '    CD-BOOKMARKS.sh:
	This script has added the ability to use bookmarks to cd.
	Examples:
		cd -b               # list bookmarks
		cd [-b] bookmark    # cd to a bookmark
		cd [-b] bookmark subdir  # cd to a directory below a bookmark
		cd -a [name] [dir]  # add/update bookmark (dir defaults to current dir)
		cd -a -s [name] [dir]  # add/update and save bookmark
		cd -S name          # save bookmark for current dir (sugar for -a -s)

	Load cd-bookmarks, in .bashrc or elsewhere:

		source /path/to/cd-bookmarks.sh

	Set your bookmarks, in .bashrc or elsewhere:
		cd_includebookmarks=1 # [optional] include bookmarks in tab completion
							  # 2 means ONLY show bookmarks
		cd_bookmarks["name"]="/path/to/bookmark" # add a bookmark
		cd_bookmarks["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"
		cd --update # re-index the bookmarks

	After updating bookmarks run `cd --update`

	The default "bookmark" is ".", but you can change that if you want.
		cd_bookmarks["default"]=".:${HOME}/projects/"

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

   ## Alias and complete
   # Replace "cd" with "cdb"
   alias cd=cdb
   complete -F _cdb cd

   # cdb: wrapper around cd with bookmark support.
   # inputs: [options] [bookmark] [subdir or path]; output: changes directory / exit status.
   function cdb {
	   local cdopts bookmark directory first_dir tmpcdpath

	   while [[ "$1" ]]; do
		   case "$1" in
			   "-a") shift; add_cd_bookmark "$@"; return;;
			   "-S") shift; add_cd_bookmark -s "$1"; return;;
			   "-p") popd || return;;
			   "-l"|"-v") dirs -v; return;;
			   "-h"|"--help") _cdb_help; return;;
			   "-b") if [[ $2 ]]; then
						 bookmark=$2; shift;
					 else
						 _cdb_show_list; return 0
					 fi;;
			   "--update") _cdb_update; return;;
			   # Everything else gets passed to cd
			   -[A-Za-z]) cdopts+=" $1";;

			   *) if [[ -z "$directory" ]]; then
					  directory=$1
				  elif [[ -z "$bookmark" ]]; then
					  bookmark=$directory
					  directory=$1
				  else
					  echo "Too many arguments"
					  return 1
				  fi;;
		   esac
		   shift
	   done

	   # Remove trailing slashes to check for hash (my_bookmark/ -> my_bookmark)
	   directory=${directory%%/}

	   ## Determine path to cd to
	   tmpcdpath=${cd_bookmarks[${bookmark:-default}]}
	   if [[ -z "$bookmark" && -z "$directory" ]]; then
		   :
	   elif [[ -z "$bookmark" && -n "$directory" && -d "$directory" ]]; then
		   # A directory, no bookmark, and the directory exists as a full path
		   tmpcdpath=.

	   elif [[ -n "$bookmark" && -z "$directory" ]]; then
		   # Bookmark, but no directory
		   if [[ -z "${cd_bookmarks[$bookmark]}" ]]; then
			   echo "Unknown bookmark: $bookmark"; return 1
		   fi
		   directory="${cd_bookmarks[$bookmark]}"
		   bookmark=default

	   elif [[ -z "$bookmark" && -n "$directory" && -n "${cd_bookmarks[$directory]}" ]]; then
		   # "Directory" which is a bookmark
		   directory="${cd_bookmarks[$directory]}"
		   tmpcdpath=
	   fi

	   if [[ -z "$bookmark" && -n "$directory" ]]; then
		   first_dir=${directory%/*}
		   first_dir=${first_dir%%/*}
		   if [[ -n "$first_dir" && -n ${cd_bookmarks[${first_dir}]} ]]; then
			   bookmark=${first_dir}
			   directory=${directory#*/}
			   tmpcdpath=${cd_bookmarks[$bookmark]}
		   fi
	   fi

	   ###############
	   ## if `pushd` is enabled add PWD when changing directories.
	   # Q: why not just pushd instead of cd?
	   # A: to respect all the flags to cd like -L or -P
	   if [[ ${cd_usepushd:-1} -eq 1 ]]; then
		   if [[ "$OLDPWD" != "$PWD" ]]; then
			   pushd . &>/dev/null
		   fi
	   fi

	   if [[ "$directory" == "-" ]]; then
		   command cd ${cdopts} - || return 1
	   elif [[ -z "$bookmark" && -z "$directory" ]]; then
		   command cd ${cdopts} || return 1
	   else
		   CDPATH="${tmpcdpath}" command cd ${cdopts} -- "$directory" || return 1
	   fi
   }


   complete -F _cdb cdb
   # _cdb: bash completion for cdb / cd-bookmarks.
   # inputs: COMP_WORDS/COMP_CWORD; output: COMPREPLY array of completions.
   function _cdb {
	   local curr prev tmpcdpath
	   curr="${COMP_WORDS[COMP_CWORD]}"
	   prev="${COMP_WORDS[COMP_CWORD-1]:-}"

	   # Default search path, overridden if previous word is a bookmark.
	   tmpcdpath=${cd_bookmarks[default]}
	   [[ ${cd_bookmarks[$prev]+x} ]] && tmpcdpath=${cd_bookmarks[$prev]}

	   # "cd -b [bookmark]" -> complete bookmark names.
	   if [[ "$prev" == "-b" ]]; then
		   compopt +o nospace
		   COMPREPLY=($(compgen -W "${bookmark_index}" -- "$curr"))
		   return
	   fi

	   # Options (cd -, -L, -P, -e, -@, --help, -b ...).
	   if [[ "$curr" == "-"* ]]; then
		   compopt +o nospace
		   COMPREPLY=($(compgen -W "- -L -P -e -@ --help -b" -- "$curr"))
		   return
	   fi

	   # Exact bookmark name -> complete to the bookmark itself.
	   if [[ -n "$curr" && ${cd_bookmarks["$curr"]+x} ]]; then
		   compopt +o nospace
		   COMPREPLY=($curr)
		   return
	   fi

	   # Normal directory completion with CDPATH set from bookmark/default.
	   compopt -o nospace
	   CDPATH=$tmpcdpath _cdb_comp "$*"

	   # Optionally mix bookmarks into top-level completion.
	   if [[ "$cd_includebookmarks" && ${#COMP_WORDS[@]} -eq 2 ]]; then
		   [[ "$cd_includebookmarks" == 2 ]] && COMPREPLY=()
		   COMPREPLY+=($(compgen -W "${bookmark_index}" -- "$curr"))

		   # Single bookmark completion: add a space after it.
		   if [[ ${#COMPREPLY[@]} -eq 1 && ${cd_bookmarks[${COMPREPLY[0]}]+x} ]]; then
			   compopt +o nospace
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
			   if [[ ( -n $mark_symdirs && -h $j || -n $mark_dirs && ! -h $j ) && ! -d ${j#"$i"/} ]]; then
				   j+="/"
			   fi
			   COMPREPLY[k++]=${j#"$i"/};
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
	   echo "Bookmarks:"
	   local maxlength=8 i
	   for i in "${!cd_bookmarks[@]}"; do
		   [[ ${#i} -gt ${maxlength} ]] && maxlength=${#i}
	   done
	   printf '  %-*s -> %s\n' "$maxlength" "[default]" "${cd_bookmarks[default]}"
	   for i in "${!cd_bookmarks[@]}"; do
		   [[ $i == "default" ]] && continue
		   printf '  %-*s -> %s\n' "$maxlength" "$i" "${cd_bookmarks[$i]}"
	   done
   }

function _cdb_update() {
    bookmark_index=''
    for i in "${!cd_bookmarks[@]}"; do
        [[ $i == "default" ]] && continue
        bookmark_index+="$i "
    done
}


	# shellcheck source=/dev/null
	[[ -f "${CD_BOOKMARK_FILE}" ]] && source "${CD_BOOKMARK_FILE}"

   # add_cd_bookmark: core helper to add/update a bookmark, optionally saving to file.
   # inputs: [-s|--save] [name] [dir]; output: updates cd_bookmarks and CD_BOOKMARK_FILE, exit status.
   add_cd_bookmark() {
	   local save=0 bookmark dir old key_line new_line tmp replaced=0

	   if [[ $1 == "-s" || $1 == "--save" ]]; then
		   save=1
		   shift
	   fi

	   bookmark=${1:-${cd_default_bookmark_name}}
	   dir=${2:-$(pwd)}

	   # Validate bookmark name (simple identifier only)
	   if [[ ! $bookmark =~ ^[A-Za-z0-9_.-]+$ ]]; then
		   echo "Invalid bookmark name: $bookmark" >> /dev/stderr
		   echo "Use only letters, digits, '.', '_' and '-'." >> /dev/stderr
		   return 1
	   fi

	   # Not a directory
	   if [[ ! -d "$dir" ]]; then
		   echo "$dir is not a directory" >> /dev/stderr
		   return 1
	   fi

	   # Set the bookmark for the session
	   old=${cd_bookmarks["$bookmark"]}
	   cd_bookmarks["$bookmark"]="$dir"

	   # No persistence requested
	   [[ $save -eq 1 ]] || { _cdb_update; return 0; }

	   key_line="cd_bookmarks[\"$bookmark\"]"
	   new_line="$key_line=\"$dir\""

	   # Ensure bookmark file and its directory exist
	   mkdir -p "$(dirname "${CD_BOOKMARK_FILE}")"
	   [[ -f "${CD_BOOKMARK_FILE}" ]] || cat <<-EOF > "${CD_BOOKMARK_FILE}"
## cd-bookmarks.sh - persistent bookmark file - see --help for more
## END
cd --update
EOF

	   tmp=$(mktemp "${CD_BOOKMARK_FILE}.XXXXXX") || return 1

	   while IFS= read -r line; do
		   case "$line" in
			   "$key_line"*)
				   if [[ -n "$old" && $replaced -eq 0 ]]; then
					   echo "warning: replacing old bookmark \"$old\"" > /dev/stderr
				   fi
				   [[ $replaced -eq 0 ]] && { echo "$new_line"; replaced=1; }
				   ;;
			   "## END")
				   [[ $replaced -eq 0 ]] && { echo "$new_line"; replaced=1; }
				   echo "$line"
				   ;;
			   *)
				   echo "$line"
				   ;;
		   esac
	   done < "${CD_BOOKMARK_FILE}" > "$tmp" && mv "$tmp" "${CD_BOOKMARK_FILE}"

	   _cdb_update
   }

   # cdb_set: convenience wrapper to add or change a bookmark and save it.
   # inputs: [name] [dir]; output: persistent bookmark in cd_bookmarks and CD_BOOKMARK_FILE.
   cdb_set() {
	   add_cd_bookmark -s "$1" "$2"
   }
