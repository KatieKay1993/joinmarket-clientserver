#!/bin/bash -x

gpg_verify_key ()
{
    gpg --keyid-format long <"$1" | grep "$2"
}

gpg_add_to_keyring ()
{
    gpg --dearmor <"$1" >>"${jm_deps}/keyring.gpg"
}

gpg_verify_sig ()
{
    gpg --no-default-keyring --keyring "${jm_deps}/keyring.gpg" --verify "$1"
}

sha256_verify ()
{
    if [ "$(uname)" == "Darwin" ]; then
        shasum -a 256 -c <<<"$1  $2"
    else
        sha256sum -c <<<"$1  $2"
    fi
}

deps_install ()
{
    if [[ ${install_os} == 'debian' ]]; then
        if deb_deps_install "python-virtualenv curl python-dev python-pip build-essential automake pkg-config libtool"; then
            return 0
        else
            return 1
        fi
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
    if ! mkdir "$1"; then
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
    fi
    rm -rf "${jm_source}/deps"
    virtualenv -p python2 "${jm_source}/jmvenv" || return 1
    source "${jm_source}/jmvenv/bin/activate" || return 1
    pip install --upgrade pip
    pip install --upgrade setuptools
    deactivate
}

openssl_get ()
{
    if [[ -z "${no_gpg_validation}" ]]; then
        openssl_file=( "${openssl_lib_tar}" "${openssl_lib_sha}" "${openssl_lib_sig}" )
        curl -L "${openssl_signer_key_url}" -o openssl_signer.key
    else
        openssl_file=( "${openssl_lib_tar}" )
    fi
    for file in ${openssl_files[@]}; do
        curl -L -O "${openssl_url}/${file}"
    done
}

openssl_build ()
{
    ./config shared --prefix="${jm_root}"
    make -j
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
    openssl_lib_sha="${openssl_lib_tar}.sha256"
    openssl_lib_sig="${openssl_lib_tar}.asc"
    openssl_url='https://www.openssl.org/source'
    openssl_signer_key_url='https://pgp.mit.edu/pks/lookup?op=get&search=0xD9C4D26D0E604491'
    openssl_signer_key_id='D9C4D26D0E604491'
    openssl_root="${jm_deps}/openssl"

    if check_skip_build 'openssl'; then
        return 0
    fi
    pushd openssl
    openssl_get
    if ! sha256_verify "${openssl_lib_tar}" "${openssl_lib_sha}"; then
        return 1
    fi
    if [[ -z "${no_gpg_validation}" ]]; then
        if gpg_verify_key openssl_signer.key "${openssl_signer_key_id}"; then
            gpg_add_to_keyring openssl_signer.key
        else
            return 1
        fi
        if gpg_verify_sig "${openssl_lib_sig}"; then
            tar -xzf "${openssl_lib_tar}"
        else
            return 1
        fi
    else
        tar -xzf "${openssl_lib_tar}"
    fi
    pushd "${openssl_version}"
    if openssl_build; then
        make install_sw
    else
        return 1
    fi
    popd
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
    patch configure.ac configure.ac.patch
}

libffi_build ()
{
    ./autogen.sh
    ./configure --disable-docs --enable-shared --prefix="${jm_root}"
    make uninstall
    make -j
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

    if check_skip_build 'libffi'; then
        return 0
    fi
    pushd libffi
    curl -L -O "${libffi_url}/${libffi_lib_tar}"
    if sha256_verify "${libffi_lib_sha}" "${libffi_lib_tar}"; then
        tar -xzf "${libffi_lib_tar}"
    else
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
    popd
}

libsodium_get ()
{
    if [[ -z "${no_gpg_validation}" ]]; then
        libsodium_files=( "${sodium_lib_tar}" "${sodium_lib_sig}" )
        curl -L "${sodium_signer_key_url}" -o libsodium_signer.key
    else
        libsodium_files=( "${sodium_lib_tar}" )
    fi
    for file in ${libsodium_files[@]}; do
        curl -L -O "${sodium_url}/${file}"
    done
}

libsodium_build ()
{
    ./autogen.sh
    ./configure --enable-shared --prefix="${jm_root}"
    make uninstall
    make -j
    if ! make check; then
        return 1
    fi
}

libsodium_install ()
{
    sodium_version='libsodium-1.0.13'
    sodium_lib_tar="${sodium_version}.tar.gz"
    sodium_lib_sig="${sodium_lib_tar}.sig"
    sodium_url='https://download.libsodium.org/libsodium/releases'
    sodium_signer_key_url='https://pgp.mit.edu/pks/lookup?op=get&search=0x210627AABA709FE1'
    sodium_signer_key_id='62F25B592B6F76DA'

    if check_skip_build 'libsodium'; then
        return 0
    fi
    pushd libsodium
    libsodium_get
    if [[ -z "${no_gpg_validation}" ]]; then
        if gpg_verify_key libsodium_signer.key "${sodium_signer_key_id}"; then
            gpg_add_to_keyring libsodium_signer.key
        else
            return 1
        fi
        if gpg_verify_sig "${sodium_lib_sig}"; then
            tar -xzf "${sodium_lib_tar}"
        else
            return 1
        fi
    else
        tar -xzf "${sodium_lib_tar}"
    fi
    pushd "${sodium_version}"
    if libsodium_build; then
        make install
    else
        return 1
    fi
    popd
    popd
}

joinmarket_install ()
{
    jm_pkgs=( 'jmbase' 'jmdaemon' 'jmbitcoin' 'jmclient' )
    for pkg in ${jm_pkgs[@]}; do
        pip uninstall -y "${pkg/jm/joinmarket}"
        pushd "${pkg}"
        pip install ${develop_build:+-e} . || return 1
        popd
    done
}

parse_flags ()
{
    for flag in ${@}; do
        case ${flag} in
            --develop)
                develop_build='1'
                ;;
            --no-gpg-validation)
                no_gpg_validation='1'
                ;;
            *)
                echo "warning.  unknown flag : ${flag}" 1>&2
                ;;
        esac
    done
}

os_is_deb ()
{
    ( which apt-get && which dpkg-query ) 2>/dev/null 1>&2
}

install_get_os ()
{
    if os_is_deb; then
        echo 'debian'
    else
        echo 'unkown'
    fi
}

qt_deps_install ()
{
    if [[ ${install_os} == 'debian' ]]; then
        if deb_deps_install "python-qt4 python-sip"; then
            return 0;
        fi
    else
        return 1
    fi
}

qt_deps_link ()
{
    if [[ ${install_os} == 'debian' ]]; then
        if deb_qt_deps_link; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

deb_qt_deps_link ()
{
    pyqt4dir="$( dpkg-query -L python-qt4 | grep -m1 "/PyQt4$" )"
    sip_so="$( dpkg-query -L python-sip | grep -m1 "sip.*.so" )"

    if [[ -r "${pyqt4dir}" ]] && [[ -r ${sip_so} ]]; then
        ln -sf -t "${VIRTUAL_ENV}/lib/python2.7/site-packages/" "${sip_so}" "${pyqt4dir}"
        return 0
    else
        return 1
    fi
}

main ()
{
    jm_source="$PWD"
    jm_root="${jm_source}/jmvenv"
    jm_deps="${jm_source}/deps"
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${jm_root}/lib/pkgconfig"
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${jm_root}/lib"
    export C_INCLUDE_PATH="${C_INCLUDE_PATH}:${jm_root}/include"

    # flags
    develop_build=''
    no_gpg_validation=''
    parse_flags ${@}

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
    mkdir -p deps
    pushd deps
    rm -f ./keyring.gpg
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
    if [[ ${install_os} != 'unknown' ]] && ! qt_deps_link; then
        read -p "
        Install Joinmarket-Qt? (may require additional dependencies)
        (y/n)  "
        if [[ ${REPLY} =~ y|Y ]]; then
            if qt_deps_install; then
                if ! qt_deps_link; then
                    echo "Qt dependencies installed but could not be found."
                fi
            else
                echo "Qt dependencies could not be installed. Joinmarket-Qt might not work."
            fi
        fi
    fi
    deactivate
    echo "Joinmarket successfully installed
    Before executing scripts or tests, run:

    \`source jmvenv/bin/activate\`

    from this directory, to activate virtualenv."
}
main ${@}
