# cd-bookmarks.sh - add bookmarks to cd (in bash)

This (ab)uses the CDPATH functionality of bash to add bookmark functionality,
with tab completion, to the built in `cd` command.  It also offers optional
pushd / popd integration.

Why: CDPATH is cool, but it's useability really sucks.  Turning it on and off,
or using aliases, or other attempts to tame it just didn't give me the desired
result.  By dynamically setting CDPATH we can have as many bookmarks as we want,
and only use them when we explicitly ask for it.

Under the hood it's all just the normal `cd` command (with some pushd and popd.
All your favorite flags like `-P` or `-@` still get passed along.

Tab completion is a slightly modified version of the normal cd completion.

`export cd_includebookmarks=1` includes the bookmarks in tab completion for the
first argument.

`export cd_includebookmarks=2` will show ONLY bookmarks in tab completion for
the first argument

Usage:

    cd -b  # list bookmarks

    cd [-b] bookmark # cd to a bookmark

	cd my_bookmark subdir
    cd -b my_bookmark subdir
	cd subdir -b my_bookmark # cd to a directory "subdir" below bookmark "my_bookmark"

    # with pushd enabled
    ~$ cd /dir1
    /dir1$ cd /dir2
    /dir2$ cd /dir3
    /dir3$ cd -p
    /dir2$ cd -p
    /dir1$ cd -p
    ~$

Setup:

Load cd-bookmarks, in .bashrc or elsewhere:

    source /path/to/cd-bookmarks.sh

And set your bookmarks:


    cd_bookmarks[project1]=/path/to/bookmark
    cd_bookmarks[project2]=/other/bookmark
    cd_bookmarks[both_projects]=/path/to/bookmark:/other/bookmark
	cd_bookmarks[local_tmp]=~/.local/tmp

	# Update the index after changing bookmarks
    cd --update

The default bookmark" is `.`, but you can change that if you want.

    cd_BOOKMARKS["default"]=.:~/work

You may optionally have it use pushd and add "cd -p" to call popd. These let you
    keep a history of the paths you have been in and return to them.

        cd -p # run "popd"
        cd -v # run "dirs -v"
        cd -c # run "dirs -c"

    e.g.:
      ~$ cd mydir

      ~/mydir$ cd /usr/mydir2

      /usr/mydir2$ cd -p

      ~/mydir$ cd -p

      ~$
