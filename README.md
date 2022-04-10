# cd-bookmarks.sh - add bookmarks to cd (in bash)

This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
with tab completion, to the built in `cd` command.

Why: CDPATH is cool, but it's useability really sucks.  Turning it on and off,
or using aliases, or other attempts to tame it just didn't give me the desired
result.  By dynamically setting CDPATH we can have as many bookmarks as we want,
and only use them when we explicitly ask for it.

Under the hood it's all just the normal `cd` command.  All your favorite flags
like `-P` or `-@` still get passed along.

Tab completion is a slightly modified version of the normal cd completion.

`export CD_INCLUDEBOOKMARKS=1` includes the bookmarks in tab completion for the
first argument.

`export CD_INCLUDEBOOKMARKS=2` will show ONLY bookmarks in tab completion for
the first argument

Usage:

    cd -b  # list bookmarks

    cd [-b] bookmark # cd to a bookmark

	cd my_bookmark subdir
    cd -b my_bookmark subdir
	cd subdir -b my_bookmark # cd to a directory "subdir" below bookmark "my_bookmark"


Setup:

Load cd-bookmarks, in .bashrc or elsewhere:

    source /path/to/cd-bookmarks.sh

And set your bookmarks:


    CD_BOOKMARKS[project1]=/path/to/bookmark
    CD_BOOKMARKS[project2]=/other/bookmark
    CD_BOOKMARKS[both_projects]=/path/to/bookmark:/other/bookmark
	CD_BOOKMARKS[local_tmp]=~/.local/tmp

	# Update the index after changing bookmarks
    cd-bookmarks-update

The default bookmark" is `.`, but you can change that if you want.

    CD_BOOKMARKS["default"]=.:~/work
