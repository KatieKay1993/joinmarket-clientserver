#!/bin/bash

sha256_verify ()
{
    if [[ "$(uname)" == "Darwin" ]]; then
        shasum -a 256 -c <<<"$1  $2"
        return "$?"
    else
        sha256sum -c <<<"$1  $2"
        return "$?"
    fi
}

deps_install ()
{
    common_deps=( \
        'python-virtualenv' \
        'curl' \
        'build-essential' \
        'automake' \
        'pkg-config' \
        'libtool' \
        'libgmp-dev' )

    if [[ ${install_os} == 'debian' ]]; then
        if is_python3; then
            deb_deps_install "${common_deps[@]} python3-dev python3-pip"
        else
            deb_deps_install "${common_deps[@]} python-dev python-pip"
        fi
        return "$?"
    else
        echo "OS can not be determined. Trying to build."
        return 0
    fi
}

deb_deps_check ()
{
    apt-cache policy ${deb_deps[@]} | grep "Installed.*none"
}

deb_deps_install ()
{
    deb_deps=( ${1} )
    if deb_deps_check; then
        clear
        echo "
            sudo password required to run :

            \`apt-get install ${deb_deps[@]}\`
            "
        if ! sudo apt-get install ${deb_deps[@]}; then
            return 1
        fi
    fi
}

check_skip_build ()
{
    if [[ ${reinstall} == false ]] && [[ -d "$1" ]]; then
        read -p "Directory ${1} exists.  Remove and recreate?  (y/n)  " q
        if [[ "${q}" =~ Y|y ]]; then
            rm -rf "./${1}"
            mkdir -p "./${1}"
            return 1
        else
            echo "skipping ${1}..."
            return 0
        fi
    fi
    return 1
}

venv_setup ()
{
    if check_skip_build 'jmvenv'; then
        return 0
    else
        reinstall='true'
    fi
    virtualenv -p "${python}" "${jm_source}/jmvenv" || return 1
    source "${jm_source}/jmvenv/bin/activate" || return 1
    pip install --upgrade pip
    pip install --upgrade setuptools
    deactivate
}

dep_get ()
{
    pkg_name="$1" pkg_hash="$2" pkg_url="$3"

    pushd cache
    if ! sha256_verify "${pkg_hash}" "${pkg_name}"; then
        curl --retry 5 -L -O "${pkg_url}/${pkg_name}"
    fi
    if ! sha256_verify "${pkg_hash}" "${pkg_name}"; then
        return 1
    fi
    tar -xzf "${pkg_name}" -C ../
    popd
}

openssl_build ()
{
    ./config shared --prefix="${jm_root}"
    make
    rm -rf "${jm_root}/ssl" \
        "${jm_root}/lib/engines" \
        "${jm_root}/lib/pkgconfig/openssl.pc" \
        "${jm_root}/lib/pkgconfig/libssl.pc" \
        "${jm_root}/lib/pkgconfig/libcrypto.pc" \
        "${jm_root}/include/openssl" \
        "${jm_root}/bin/c_rehash" \
        "${jm_root}/bin/openssl"
    if ! make test; then
        return 1
    fi
}

openssl_install ()
{
    openssl_version='openssl-1.0.2l'
    openssl_lib_tar="${openssl_version}.tar.gz"
    openssl_lib_sha='ce07195b659e75f4e1db43552860070061f156a98bb37b672b101ba6e3ddf30c'
    openssl_url='https://www.openssl.org/source'

    if check_skip_build "${openssl_version}"; then
        return 0
    fi
    if ! dep_get "${openssl_lib_tar}" "${openssl_lib_sha}" "${openssl_url}"; then
        return 1
    fi
    pushd "${openssl_version}"
    if openssl_build; then
        make install_sw
    else
        return 1
    fi
    popd
}

# add '--disable-docs' to libffi ./configure so makeinfo isn't needed
# https://github.com/libffi/libffi/pull/190/commits/fa7a257113e2cfc963a0be9dca5d7b4c73999dcc
libffi_patch_disable_docs ()
{
    cat <<'EOF' > Makefile.am.patch
56c56,59
< info_TEXINFOS = doc/libffi.texi
---
> info_TEXINFOS =
> if BUILD_DOCS
> #info_TEXINFOS += doc/libffi.texi
> endif
EOF

    # autogen.sh is not happy when run from some directories, causing it
    # to create an ltmain.sh file in our ${jm_root} directory.  weird.
    # https://github.com/meetecho/janus-gateway/issues/290#issuecomment-125160739
    # https://github.com/meetecho/janus-gateway/commit/ac38cfdae7185f9061569b14809af4d4052da700
    cat <<'EOF' > autoreconf.patch
18a19
> AC_CONFIG_AUX_DIR([.])
EOF

    cat <<'EOF' > configure.ac.patch
545a546,552
> AC_ARG_ENABLE(docs,
>               AC_HELP_STRING([--disable-docs],
>                              [Disable building of docs (default: no)]),
>               [enable_docs=no],
>               [enable_docs=yes])
> AM_CONDITIONAL(BUILD_DOCS, [test x$enable_docs = xyes])
> 
EOF
    patch Makefile.am Makefile.am.patch
    patch configure.ac autoreconf.patch
    patch configure.ac configure.ac.patch
}

libffi_build ()
{
    ./autogen.sh
    ./configure --disable-docs --enable-shared --prefix="${jm_root}"
    make uninstall
    make
    if ! make check; then
        return 1
    fi
}

libffi_install ()
{
    libffi_version='libffi-3.2.1'
    libffi_lib_tar="v3.2.1.tar.gz"
    libffi_lib_sha='96d08dee6f262beea1a18ac9a3801f64018dc4521895e9198d029d6850febe23'
    libffi_url="https://github.com/libffi/libffi/archive"

    if check_skip_build "${libffi_version}"; then
        return 0
    fi
    if ! dep_get "${libffi_lib_tar}" "${libffi_lib_sha}" "${libffi_url}"; then
        return 1
    fi
    pushd "${libffi_version}"
    if ! libffi_patch_disable_docs; then
        return 1
    fi
    if libffi_build; then
        make install
    else
        return 1
    fi
    popd
}

libsodium_build ()
{
    make uninstall
    make distclean
    ./autogen.sh
    ./configure \
        --enable-minimal \
        --enable-shared \
        --prefix="${jm_root}"
    make uninstall
    make
    if ! make check; then
        return 1
    fi
}

libsodium_install ()
{
    sodium_version='libsodium-1.0.13'
    sodium_lib_tar="${sodium_version}.tar.gz"
    sodium_lib_sha='9c13accb1a9e59ab3affde0e60ef9a2149ed4d6e8f99c93c7a5b97499ee323fd'
    sodium_url='https://download.libsodium.org/libsodium/releases/old'

    if check_skip_build "${sodium_version}"; then
        return 0
    fi
    if ! dep_get "${sodium_lib_tar}" "${sodium_lib_sha}" "${sodium_url}"; then
        return 1
    fi
    pushd "${sodium_version}"
    if libsodium_build; then
        make install
    else
        return 1
    fi
    popd
}

joinmarket_install ()
{
    reqs=()
    if ! is_python3 ; then
        req_pfx='py2-'
    fi

    if [[ -n "${develop_build}" ]]; then
        reqs+=( 'develop.txt' )
    else
        reqs+=( 'production.txt' )
    fi
    if [[ -n ${with_qt} ]]; then
        reqs+=( 'gui.txt' )
    fi

    for req in ${reqs[@]}; do
        pip install -r "requirements/${req_pfx}${req}" || return 1
    done
}

parse_flags ()
{
    while :; do
        case $1 in
            --develop)
                develop_build='1'
                ;;
            -p|--python)
                if [[ "$2" ]]; then
                    python="$2"
                    shift
                else
                    echo 'ERROR: "--python" requires a non-empty option argument.'
                    return 1
                fi
                ;;
            --python=?*)
                python="${1#*=}"
                ;;
            --python=)
                echo 'ERROR: "--python" requires a non-empty option argument.'
                return 1
                ;;
            --with-qt)
                with_qt='1'
                ;;
            "")
                break
                ;;
            *)
                echo "
Usage: "${0}" [options]

Options:

--develop       code remains editable in place
--python, -p    python version (default: python3)
--with-qt       build the Qt GUI (incompatible with python2)
"
                return 1
                ;;
        esac
        shift
    done

    if [[ ${with_qt} == 1 ]] && [[ ${python} == python2* ]]; then
        echo "ERROR: Joinmarket-Qt is currently only available for Python 3
                     Use the flag '--python=python3' to enable a python3 install."
        return 1
    elif [[ ${with_qt} != 1 ]] && [[ ${python} == python3* ]]; then
        read -p "
        INFO: Joinmarket-Qt for GUI Taker and Tumbler modes is available.
        Install Qt dependencies (~160mb) ? [y|n] : "
        if [[ ${REPLY} =~ y|Y ]]; then
            with_qt='1'
        fi
    fi
}

os_is_deb ()
{
    ( which apt-get && which dpkg-query ) 2>/dev/null 1>&2
}

is_python3 ()
{
    if [[ ${python} == python3* ]]; then
        return 0
    fi
    if [[ ${python} == python2* ]]; then
        return 1
    fi
    ${python} -c 'import sys; sys.exit(0) if sys.version_info >= (3,0) else sys.exit(1)'
}

install_get_os ()
{
    if os_is_deb; then
        echo 'debian'
    else
        echo 'unknown'
    fi
}

main ()
{
    jm_source="$PWD"
    jm_root="${jm_source}/jmvenv"
    jm_deps="${jm_source}/deps"
    export PKG_CONFIG_PATH="${jm_root}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${jm_root}/lib:${LD_LIBRARY_PATH}"
    export C_INCLUDE_PATH="${jm_root}/include:${C_INCLUDE_PATH}"
    export MAKEFLAGS='-j'

    # flags
    develop_build=''
    no_gpg_validation=''
    python='python3'
    with_qt=''
    reinstall='false'
    if ! parse_flags ${@}; then
        return 1
    fi

    # os check
    install_os="$( install_get_os )"

    if ! deps_install; then
        echo "Dependecies could not be installed. Exiting."
        return 1
    fi
    if ! venv_setup; then
        echo "Joinmarket virtualenv could not be setup. Exiting."
        return 1
    fi
    source "${jm_root}/bin/activate"
    mkdir -p "deps/cache"
    pushd deps
# openssl build disabled. using OS package manager's version.
#    if ! openssl_install; then
#        echo "Openssl was not built. Exiting."
#        return 1
#    fi
    if ! libffi_install; then
        echo "Libffi was not built. Exiting."
        return 1
    fi
    if ! libsodium_install; then
        echo "Libsodium was not built. Exiting."
        return 1
    fi
    popd
    if ! joinmarket_install; then
        echo "Joinmarket was not installed. Exiting."
        deactivate
        return 1
    fi
    deactivate
    echo "Joinmarket successfully installed
    Before executing scripts or tests, run:

    \`source jmvenv/bin/activate\`

    from this directory, to activate virtualenv."
}
main ${@}
