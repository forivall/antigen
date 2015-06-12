export _ANTIGEN_CACHE_DIR=$_ANTIGEN_INSTALL_DIR/.cache/
export _ANTIGEN_BUNDLE_CACHE=$_ANTIGEN_CACHE_DIR/.zcache
export _ANTIGEN_BUNDLE_CACHE_LOAD=$_ANTIGEN_CACHE_DIR/.zcache.load

# Be sure .cache directory exists
[[ ! -e $_ANTIGEN_CACHE_DIR ]] && mkdir $_ANTIGEN_CACHE_DIR
local extensions_paths=""

# TODO Merge this code with -antigen-load function to avoid duplication
-antigen-dump-file-list () {

    local url="$1"
    local loc="$2"
    local make_local_clone="$3"

    # The full location where the plugin is located.
    local location
    if $make_local_clone; then
        location="$(-antigen-get-clone-dir "$url")/"
    else
        location="$url/"
    fi

    [[ $loc != "/" ]] && location="$location$loc"

    if [[ -f "$location" ]]; then
        echo "$location"

    else

        # Source the plugin script.
        # FIXME: I don't know. Looks very very ugly. Needs a better
        # implementation once tests are ready.
        local script_loc="$(ls "$location" | grep '\.plugin\.zsh$' | head -n1)"

        if [[ -f $location/$script_loc ]]; then
            # If we have a `*.plugin.zsh`, source it.
            echo "$location/$script_loc"

        elif [[ -f $location/init.zsh ]]; then
            # If we have a `init.zsh`
            # if (( $+functions[pmodload] )); then
                # If pmodload is defined pmodload the module. Remove `modules/`
                # from loc to find module name.
                #pmodload "${loc#modules/}"
            # else
                # Otherwise source it.
                echo "$location/init.zsh"
            # fi

        elif ls "$location" | grep -l '\.zsh$' &> /dev/null; then
            # If there is no `*.plugin.zsh` file, source *all* the `*.zsh`
            # files.
            for script ($location/*.zsh(N)) { echo "$script" }

        elif ls "$location" | grep -l '\.sh$' &> /dev/null; then
            # If there are no `*.zsh` files either, we look for and source any
            # `*.sh` files instead.
            for script ($location/*.sh(N)) { echo "$script" }

        fi

    fi
}

function -dots-start-capture () {
    dots__capture__file=$1
    dots__capture__file_load=$2

    # remove prior cache file
    [ -f "$dots__capture__file" ] && rm -f $dots__capture__file
    [ -f "$dots__capture__file_load" ] && rm -f $dots__capture__file_load

    echo " # START ZCACHE GENERATED FILE" >>! $dots__capture__file_load

    # save current -antigen-load and shim in a version
    # that logs calls to the catpure file
    eval "function -dots-original$(functions -- -antigen-load)"
    function -antigen-load () {
        local location=$(-antigen-dump-file-list "$1" "$2" "$3")

        if [[ ! $location == "" ]]; then
            cat $location >>! $dots__capture__file_load
            echo ";\n" >>! $dots__capture__file_load
            extensions_paths="$extensions_paths $location"

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

function -dots-intercept-bundle () {
    eval "function -bundle-intercepted-$(functions -- antigen-bundle)"
    function antigen-bundle () {
        echo "$@" >>! $_ANTIGEN_BUNDLE_CACHE
        -bundle-intercepted-antigen-bundle "$@"
    }
}

function -dots-deintercept-bundle () {
    eval "function $(functions -- -bundle-intercepted-antigen-bundle | sed 's/-bundle-intercepted-//')"
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
        -dots-intercept-bundle
    fi
}

function -zcache-done () {
    if ! $_ANTIGEN_CACHE_ENABLED; then
        return
    fi

    if ! $__ZCACHE_CAPTURING; then
        -dots-enable-bundle
        return
    else
        -dots-deintercept-bundle
    fi

    echo "fpath=($extensions_paths $fpath)" >>! $_ANTIGEN_BUNDLE_CACHE_LOAD
    echo  " # END ZCACHE GENERATED FILE" >>! $_ANTIGEN_BUNDLE_CACHE_LOAD

    # TODO add option
    # if $_ANTIGEN_CACHE_MINIFY; then
        sed -i '/^#.*/d' $_ANTIGEN_BUNDLE_CACHE_LOAD
        sed -i '/^$/d' $_ANTIGEN_BUNDLE_CACHE_LOAD
        sed -i '/./!d' $_ANTIGEN_BUNDLE_CACHE_LOAD
    # fi

    -dots-stop-capture $_ANTIGEN_BUNDLE_CACHE
}

function -zcache-clear () {
    [[ -e $_ANTIGEN_BUNDLE_CACHE ]] && rm $_ANTIGEN_BUNDLE_CACHE
    [[ -e $_ANTIGEN_BUNDLE_CACHE_LOAD ]] && rm $_ANTIGEN_BUNDLE_CACHE_LOAD
}

function -zcache-rebuild () {
    local bundles="$(cat $_ANTIGEN_BUNDLE_CACHE)"
    -zcache-clear
    -zcache-start
    echo $bundles | while read line; do
        eval "antigen-bundle $line"
    done
    -zcache-done
}
