#
# MOONSHELL FUNCTIONS
#

# 'moonshell' is a tab completion conflict with 'moonshot' and it's rare that a
# person should need to use this function during their every day, but it is a
# nice to have for when you are developing it. In the mean time, however, we
# 'hide' it as '_moonshell' to not impact functionality and use.
_moonshell () {
    local options=($@)
    [[ -z ${options} ]] \
        && _moonshell_help \
        || _moonshell_getopts ${options[@]}
}

_moonshell_getopts () {
    OPTIND=1
    local optspec=":hrst" OPTARG=($@)
    # Long options don't actually work in this case, but it works enough to
    # give the illusion that it does.
    while getopts "${optspec}" opt; do
        case "${opt}" in
            h|help)
                _moonshell_help
                return 0
            ;;
            r|reset)
                _moonshell_reset
                return 0
            ;;
            s|setup)
                _moonshell_setup
                return 0
            ;;
            t|test)
                _moonshell_test
                return 0
            ;;
        esac
    done
}

_moonshell_help () {
    cat << EOF
Usage: _moonshell [-h|--help] [-r|--reset] [-s|--setup]
Perform basic functions for Moonshell.

    -h, --help      show this help and exit
    -r, --reset     remove all var files and regenerate self
    -s, --setup     install self in to the shell of the running user
    -t, --test      run bashate, rubocop and markdownlint
EOF
}

_moonshell_overlay_dir () {
    # The purpose of 'overlay' is to extend functionality of Moonshell. If you
    # have developed a library or script that is only relevant to one of your
    # Moonshot stacks/projects, then you can overlay a custom bin/, lib/ or
    # profile.d/ dir to override default Moonshell behaviour, or extend it.
    #
    local dir=$1
    local overlay="${MOON_PROFILE}/private/overlay.sh"
    local -a locations=(lib etc/profile.d etc/completion.d)

    [[ ! -d ${dir} ]] \
        && echoerr "ERROR: '${dir}' does not exist or is not a directory" \
        && return 1

    [[ ! -f ${overlay} ]] \
        && mkdir -p "${MOON_PROFILE}/private" \
        && touch ${overlay}

    [[ $(grep -c "${dir}" ${overlay}) == 0 ]] \
        && echo "_moonshell_overlay_dir ${dir}" >> ${overlay}

    [[ -d ${dir}/bin ]] && _moonshell_path_add "${dir}/bin"

    for location in ${locations[@]}; do
        [[ -d "${dir}/${location}" ]] && _moonshell_source "${dir}/${location}"
    done
}

_moonshell_path_add () {
    local bin_dir=$1

    [[ ! "${PATH}" =~ "${bin_dir}" ]] \
        && export PATH=${bin_dir}:${PATH}
}

_moonshell_reset () {
    echoerr "Reinitialising Moonshell.."
    [[ -z ${MOON_VAR-} ]] \
        && echoerr "ERROR: \${MOON_VAR} is unset; run 'moonshell --setup'" \
        && return 1 \
        || rm -Rf ${MOON_VAR}/*
    source ${MOON_ROOT}/moon.sh
}

_moonshell_setup () {
    echoerr "Running Moonshell setup"
    _moonshell_self_check $(realpath $(readlink -f ${MOON_ROOT}))
}

_moonshell_source () {
    local source_dir=$1

    for source_file in $(find ${source_dir}/ ${MOON_FIND_OPTS} -name '*.sh'); do
        source "${source_file}"
    done
}

_moonshell_test () {
    pushd ${MOON_ROOT} >/dev/null
        echoerr "Testing shell..."
        bashate -i E006,E042 moon.sh $(find -name "*.sh")
        echoerr "Testing markdown..."
        mdl $(find -name "*.md")
        echoerr "Testing ruby..."
        bundle exec rubocop -D
    popd >/dev/null
}


#
# MOONSHELL SELF FUNCTIONS
#
_moonshell_self_check () {
    local moonshell_dir=$1

    # For now we are tied to this being set thusly
    local moonshell_home_link="${HOME}/.moonshell"

    _moonshell_self_check_link ${moonshell_home_link} ${moonshell_dir}
    _moonshell_self_check_bashrc ${moonshell_home_link}
    _moonshell_self_check_gems ${moonshell_home_link}
}

_moonshell_self_check_link () {
    local moonshell_home_link=$1
    local moonshell_dir=$2

    local moonshell_home_link_target
    local moonshell_home_link_path

    if [[ -d ${moonshell_home_link} ]]; then
        if [[ -L ${moonshell_home_link} ]]; then
            # Handle recursive symlinking
            moonshell_home_link_target=$(readlink ${moonshell_home_link})
            if [[ -L ${moonshell_home_link_target} ]]; then
                echoerr "ERROR: '${moonshell_home_link_target}' is a recursive link"
                if _moonshell_self_fix "Fix recursive link?"; then
                    unlink ${moonshell_home_link_target}
                    _moonshell_self_fix_link ${moonshell_dir} ${moonshell_home_link}
                fi
            fi

            moonshell_home_link_dir=$(realpath ${moonshell_home_link})
            if [[ ! ${moonshell_home_link_dir} == ${moonshell_dir} ]] && [[ ! -L ${moonshell_dir} ]]; then
                echoerr "WARNING: Moonshell is linked to a different checkout"
                echoerr "  current: ${moonshell_home_link_dir}"
                echoerr "  proposed: ${moonshell_dir}"
                if _moonshell_self_fix "Update the link? (y/N) "; then
                    _moonshell_self_fix_link ${moonshell_dir} ${moonshell_home_link}
                fi
            fi
        else
            echoerr "INFO ${moonshell_home_link} is a directory, not a symlink"
        fi
    else
        echoerr "WARNING: Home link to Moonshell not present '${moonshell_home_link}'. Creating"
        _moonshell_self_fix_link ${moonshell_dir} ${moonshell_home_link}
    fi
}

_moonshell_self_check_bashrc () {
    local moonshell_home_link=$1

    local bash_file="${HOME}/$(bash_rc_file)"
    local grep_bin=$(which grep | tail -1)
    local installed=$(${grep_bin} -v '^#' ${bash_file} | ${grep_bin} -c "${moonshell_home_link}/moon.sh" 2>/dev/null)

    if [[ ${installed} == 0 ]]; then
        echoerr "WARNING: 'moon.sh' is not being sourced from ${bash_file}"
        if _moonshell_self_fix "Append source?"; then
            _moonshell_self_fix_bashrc ${bash_file} ${moonshell_home_link}
        fi
    fi
}

_moonshell_self_check_gems () {
    local moonshell_home_link=$1

    local grep_bin=$(which grep | tail -1)
    local bundle_install
    local gem
    local gems=($(${grep_bin} ^gem "${moonshell_home_link}/Gemfile" | tr -d "'" | awk '{print $2}'))

    for gem in ${gems[@]-}; do
        [[ ! -f ${moonshell_home_link}/Gemfile.lock ]] \
            && bundle_install=true \
            && break
        [[ $(${grep_bin} -c ${gem} ${moonshell_home_link}/Gemfile.lock) == 0 ]] \
            && bundle_install=true \
            && break
    done

    if [[ ${bundle_install-} ]]; then
        if _moonshell_self_fix "Bundle install missing gems?"; then
            _moonshell_self_fix_gems ${moonshell_home_link}
        else
            echoerr "INFO: Skipping bundle install"
        fi
    fi
}

_moonshell_self_fix () {
    local message=$1
    local fix

    echo -n "${message} (y/N) "
    read fix
    [[ ${fix} =~ ^[y|Y]$ ]] \
        && return 0 \
        || return 1
}

_moonshell_self_fix_bashrc () {
    local bash_file=$1
    local moonshell_home_link=$2

    echo >> ${bash_file}
    echo "# Moonshell: because setting up Bash for managing space travel shouldn't be a moonshot" >> ${bash_file}
    echo "#export DEBUG=true" >> ${bash_file}
    echo "source ${moonshell_home_link}/moon.sh" >> ${bash_file}
}

_moonshell_self_fix_link () {
    local src=$1
    local dst=$2
    ln -sv ${src} ${dst}
}

_moonshell_self_fix_gems () {
    local moonshell_home_link=$1

    bundle_bin=$(which bundle 2>/dev/null || true)
    [[ -z ${bundle_bin-} ]] \
        && echoerr "ERROR: 'bundle' command not found" \
        && return 1

    echoerr "INFO: Installing ruby gems"
    pushd ${moonshell_home_link} >/dev/null
        bundle install
    popd >/dev/null
}

