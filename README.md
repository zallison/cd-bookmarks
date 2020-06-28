# cd-bookmarks.sh - bookmarks with cd


This (ab)uses the CDPATH functionality of bash to add bookmark functionality.

Examples:

`cd [-b] bookmark`

`cd [-b] bookmark subdir`

If a bookmark and a directory share a name, the local directory takes precedence.

`CD_BOOKMARKS["name"]="/path/to/bookmark"`

`CD_BOOKMARKS["mulitpath"]="/path/to/bookmark1:/path/to/bookmark2"`

After updating bookmarks run `cd-bookmarks-update`

* Known Issues

Other CD flags are not passed, such as
    -L -P -e -@
