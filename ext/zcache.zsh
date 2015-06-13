export _ANTIGEN_CACHE_DIR=$_ANTIGEN_INSTALL_DIR/.cache/

# Be sure .cache directory exists
[[ ! -e $_ANTIGEN_CACHE_DIR ]] && mkdir $_ANTIGEN_CACHE_DIR

local _zcache_extensions_paths=""
local _zcache_context=""
local _zcache_capturing=false
local _zcache_meta_path=""
local _zcache_payload_path=""
local dots__capture__file_load=""
local dots__capture__file=""

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

    echo " # START ZCACHE GENERATED FILE" >>! $dots__capture__file

    # save current -antigen-load and shim in a version
    # that logs calls to the catpure file
    eval "function -dots-original$(functions -- -antigen-load)"
    function -antigen-load () {
        -antigen-dump-file-list "$1" "$2" "$3" | while read line; do
            if [[ ! $line == "" ]]; then
                cat $line >>! $dots__capture__file
                echo ";\n" >>! $dots__capture__file
                _zcache_extensions_paths="$extensions_paths $line"

                -dots-original-antigen-load "$@"
            fi
        done
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
        echo "$@" >>! $_zcache_meta_path
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

    # Set up the context
    _zcache_context="$1"
    _zcache_capturing=false
    _zcache_meta_path="$_ANTIGEN_CACHE_DIR/.zcache.$_zcache_context-meta"
    _zcache_payload_path="$_ANTIGEN_CACHE_DIR/.zcache.$_zcache_context-payload"

    if [ -f "$_zcache_payload_path" ] ; then
        source "$_zcache_payload_path" # cache exists, load it
        -dots-disable-bundle          # disable bundle so it won't load bundle twice
    else
        _zcache_capturing=true       # mark capturing
        -dots-start-capture $_zcache_payload_path
        -dots-intercept-bundle
    fi
}

function -zcache-done () {
    if ! $_ANTIGEN_CACHE_ENABLED; then
        return
    fi

    if ! $_zcache_capturing; then
        -dots-enable-bundle
        return
    else
        -dots-deintercept-bundle
    fi

    echo "fpath=($_zcache_extensions_paths $fpath)" >>! $_zcache_payload_path
    echo  " # END ZCACHE GENERATED FILE" >>! $_zcache_payload_path

    # TODO add option
    # if $_ANTIGEN_CACHE_MINIFY; then
        sed -i '/^#.*/d' $_zcache_payload_path
        sed -i '/^$/d' $_zcache_payload_path
        sed -i '/./!d' $_zcache_payload_path
    # fi

    -dots-stop-capture $_zcache_meta_path
}

function -zcache-clear () {
    if [ -d "$_ANTIGEN_CACHE_DIR" ]; then
        # TODO how compatible is this -A flag?
        ls -A "$_ANTIGEN_CACHE_DIR" | while read file; do
            rm "$_ANTIGEN_CACHE_DIR/$file"
        done
    fi
}

function -zcache-rebuild () {
    local bundles=""
    local context=""

    ls -A "$_ANTIGEN_CACHE_DIR" | while read file; do
        if [[ $file == *-meta ]]; then
            context=$(echo $file | sed 's/.zcache.//' | sed 's/-meta//')
            -zcache-start $context
            cat "$_ANTIGEN_CACHE_DIR/$file" | while read line; do
                eval "antigen-bundle $line"
            done
            -zcache-done
        fi
    done
}
