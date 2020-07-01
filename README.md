# cd-bookmarks.sh - bookmarks with cd


This (ab)uses the CDPATH functionality of bash to add bookmark functionality, with tab completion.

Why:  CDPATH is cool, but it's useability really sucks.  Turning it on and off, or using aliases, or other attempts to tame it just didn't give me the desired result.  This allows us to dynamically set CDPATH for just this command.  And not just one CDPATH, but as many as you want!

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

    CD_BOOKMARKS["default"]=".:${HOME}/projects/"
