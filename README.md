# cd-bookmarks.sh - add bookmarks to cd (in bash)

This (ab)uses the CDPATH functionality of bash to add bookmark functionality, with tab completion, to the built in `cd` command.

Why:  CDPATH is cool, but it's useability really sucks.  Turning it on and off, or using aliases, or other attempts to tame it just didn't give me the desired result.  By dynamically setting CDPATH we can have as many bookmarks as we want, and only use them when we explicitly ask for it.

Under the hood it's all just the normal `cd` command.  All your favorite flags like `-P` or `-@` still get passed along.  The completion is a slightly modified version of the normal cd completion.

There's an environment variable to control if bookmarks should be shown default, or only after "-b".  Setting `CD_INCLUDEBOOKMARKS=1` makes the bookmarks show like they're directories in a remote dirpath.  If you like it cool, if not then leave it off.

Examples:

Load cd-bookmarks, in .bashrc or elsewhere:

    source /path/to/cd-bookmarks.sh

Set your bookmarks, in .bashrc or elsewhere:

    CD_BOOKMARKS["name"]="/path/to/bookmark"

    CD_BOOKMARKS["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"

    cd-bookmarks-update

Usage:

    cd -b  # list bookmarks

    cd [-b] bookmark # cd to a bookmark

    cd [-b] bookmark subdir # cd to a directory below a bookmark


After updating bookmarks run `cd-bookmarks-update`

The default "bookmark" is ".", but you can change that if you want.

    CD_BOOKMARKS["default"]=".:${HOME}/projects/"
