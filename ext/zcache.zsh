export _ANTIGEN_CACHE_DIR=$_ANTIGEN_INSTALL_DIR/.cache/
export _ANTIGEN_BUNDLE_CACHE=$_ANTIGEN_CACHE_DIR/.zcache
export _ANTIGEN_BUNDLE_CACHE_LOAD=$_ANTIGEN_CACHE_DIR/.zcache.load

# Be sure .cache directory exists
[[ ! -e $_ANTIGEN_CACHE_DIR ]] && mkdir $_ANTIGEN_CACHE_DIR
local extensions_paths

function -dots-start-capture () {
    dots__capture__file=$1
    dots__capture__file_load=$2

    # remove prior cache file
    [ -f "$dots__capture__file" ] && rm -f $dots__capture__file
    [ -f "$dots__capture__file_load" ] && rm -f $dots__capture__file_load

    # save current -antigen-load and shim in a version
    # that logs calls to the catpure file
    eval "function -dots-original$(functions -- -antigen-load)"
    function -antigen-load () {
        local location=$(-antigen-dump-file-list "$1" "$2" "$3")

        echo "# START ZCACHE GENERATED FILE" >>! $dots__capture__file_load
        if [[ ! $location == "" ]]; then
          cat $location >>! $dots__capture__file_load
          extensions_paths="$extensions_paths $location"

          echo "\n;\n# End of loaded file\n;\n# Start of loaded file\n ;" >>! $dots__capture__file_load
          echo -antigen-load "$@" >>! $dots__capture__file

          -dots-original-antigen-load "$@"
        fi
    }
}

function -dots-stop-capture () {
    # unset catpure file var and restore intercepted -antigen-load
    unset dots__capture__file
    eval "function $(functions -- -dots-original-antigen-load | sed 's/-dots-original//')"
}

function -dots-disable-bundle () {
    eval "function -bundle-original-$(functions -- antigen-bundle)"
    function antigen-bundle () {}
}

function -dots-enable-bundle () {
    eval "function $(functions -- -bundle-original-antigen-bundle | sed 's/-bundle-original-//')"
}

function -zcache-start () {
    if ! $_ANTIGEN_CACHE_ENABLED; then
        return
    fi

    __ZCACHE_CAPTURING=false
    if [ -f $_ANTIGEN_BUNDLE_CACHE ] ; then
        source $_ANTIGEN_BUNDLE_CACHE_LOAD # cache exists, load it
        -dots-disable-bundle          # disable bundle so it won't load bundle twice
    else
        __ZCACHE_CAPTURING=true       # mark capturing
        -dots-start-capture $_ANTIGEN_BUNDLE_CACHE $_ANTIGEN_BUNDLE_CACHE_LOAD
    fi
}

function -zcache-done () {
    if ! $_ANTIGEN_CACHE_ENABLED; then
        return
    fi

    echo "\nfpath=($extensions_paths $fpath);\n" >>! $_ANTIGEN_BUNDLE_CACHE_LOAD
    echo  " # END ZCACHE GENERATED FILE" >>! $_ANTIGEN_BUNDLE_CACHE_LOAD
    -dots-stop-capture $_ANTIGEN_BUNDLE_CACHE

    if ! $__ZCACHE_CAPTURING; then
        -dots-enable-bundle
    fi

}

function -zcache-clear () {
  [[ -e $_ANTIGEN_BUNDLE_CACHE ]] && rm $_ANTIGEN_BUNDLE_CACHE
  [[ -e $_ANTIGEN_BUNDLE_CACHE_LOAD ]] && rm $_ANTIGEN_BUNDLE_CACHE_LOAD
}
