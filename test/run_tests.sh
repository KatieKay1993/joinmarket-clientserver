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

is_travis_osx ()
{
    if [[ "${HAS_JOSH_K_SEAL_OF_APPROVAL}" == true ]] && [[ "${TRAVIS_OS_NAME}" == osx ]]; then
        return 0
    else
        return 1
    fi
}

is_venv_active ()
{
    if [[ -z "${VIRTUAL_ENV}" ]]; then
        echo "Source JM virtualenv before running tests:

        \`source ./jmvenv/bin/activate\`"
        return 1
    fi
}

get_core_osx ()
{
    core_version='0.16.2'
    core_dist="bitcoin-${core_version}-osx64.tar.gz"
    core_url="https://bitcoincore.org/bin/bitcoin-core-${core_version}/${core_dist}"
    core_sha='64e7d96d0497112aa808ff94e63eb18bff1535cf6237e7c1d602f0fca167e863'

    if ! sha256_verify "${core_sha}" "${core_dist}"; then
        curl --retry 5 -L "${core_url}" -o "${core_dist}"
    fi
    if sha256_verify "${core_sha}" "${core_dist}"; then
        tar -xzf "${core_dist}" -C "${jm_deps}/"
        export PATH="${jm_deps}/bitcoin-${core_version}/bin:${PATH}"
    else
        echo "Bitcoin Core not installed. Exiting."
        return 1
    fi
}

get_tests_deps ()
{
    pushd "${jm_deps}/cache"
    if is_travis_osx; then
        if ! get_core_osx; then
            return 1
        fi
    fi
    if [[ ! -x "$(command -v bitcoind)" ]]; then
        echo "bitcoind not found in PATH. Exiting"
        return 1
    fi
    miniircd_sha="1c118fd8a9b55e150ad2a2f19d70b9f290e26e6757d2233984a50224b473f0cd"
    if ! sha256_verify "${miniircd_sha}" "./miniircd.tar.gz"; then
        curl --retry 5 -L https://github.com/JoinMarket-Org/miniircd/archive/master.tar.gz -o miniircd.tar.gz
    fi
    if sha256_verify "${miniircd_sha}" "./miniircd.tar.gz"; then
        rm -rf "${jm_root}/miniircd"
        mkdir -p "${jm_root}/miniircd"
        tar -xzf miniircd.tar.gz -C "${jm_root}/miniircd" --strip-components=1
    else
        echo "miniircd not installed. Exiting."
        return 1
    fi
    popd
    if ! pip install -r ./requirements-dev.txt; then
        echo "Packages in 'requirements-dev.txt' could not be installed. Exiting."
        return 1
    fi
}

set_jm_cfg ()
{
    if [[ ! -L ./joinmarket.cfg && -e ./joinmarket.cfg ]]; then
        mv ./joinmarket.cfg ./joinmarket.cfg.bak
		echo "file 'joinmarket.cfg' moved to 'joinmarket.cfg.bak'"
    fi
    unlink ./joinmarket.cfg
    ln -s ./test/regtest_joinmarket.cfg ./joinmarket.cfg
}

set_osx_ramdisk ()
{
    ramdev="$( hdiutil attach -nomount ram://4194304 | tr -d '[:space:]' )"
    diskutil erasevolume HFS+ 'ramdisk' "${ramdev}"
}

set_jm_datadir ()
{
    if is_travis_osx; then
        set_osx_ramdisk
    fi
    for dir in '/dev/shm' '/Volumes/ramdisk' '/tmp' "${jm_root}/test"; do
        if [[ -d "${dir}" && -r "${dir}" && -w "${dir}" && -x "${dir}" ]]; then
            jm_test_datadir="${dir}/jm_test_home/.bitcoin"
            break
        fi
    done
    if [[ -z "${jm_test_datadir}" ]]; then
        echo "No candidate directory for test files. Exiting."
        return 1
    fi
    orig_umask="$(umask -p)"
    umask 077
    rm -rf "${jm_test_datadir}"
    mkdir -p "${jm_test_datadir}"
    cp -vf ./test/bitcoin.conf "${jm_test_datadir}/bitcoin.conf"
    ${orig_umask}
    if ! [[ -r "${jm_test_datadir}/bitcoin.conf" ]]; then
        "Regtest datadir does not exist. Exiting."
        return 1
    fi
    echo "datadir=${jm_test_datadir}" >> "${jm_test_datadir}/bitcoin.conf"
}

run_jm_tests ()
{
    python -m py.test \
        ${HAS_JOSH_K_SEAL_OF_APPROVAL+--cov=jmclient --cov=jmbitcoin --cov=jmbase --cov=jmdaemon --cov-report html} \
        --btcpwd=123456abcdef \
        --btcconf=${jm_test_datadir}/bitcoin.conf \
        --btcuser=bitcoinrpc \
        --nirc=2 \
        -p no:warnings \
        -k "not configure"
    return "$?"
}

tests_cleanup ()
{
    if [[ "${HAS_JOSH_K_SEAL_OF_APPROVAL}" == true ]] && (( ${success} != 0 )); then
        echo -e '\n\n--- debug.log last 100 lines ---\n'
        tail -100 "${jm_test_datadir}/regtest/debug.log"
        echo -e '\n\n--- datadir contents ---\n'
        find "${jm_test_datadir}"
        echo -e '\n------'
    else
        rm -rf "${jm_test_datadir}"
        unlink ./joinmarket.cfg
        if read bitcoind_pid <"${jm_test_datadir}/bitcoind.pid"; then
            kill -15 ${bitcoind_pid} || kill -9 ${bitcoind_pid}
        fi
    fi
}

main ()
{
    if is_venv_active; then
        jm_root="${VIRTUAL_ENV}/.."
        jm_deps="${jm_root}/deps"
        export PKG_CONFIG_PATH="${VIRTUAL_ENV}/lib/pkgconfig:${PKG_CONFIG_PATH}"
        export LD_LIBRARY_PATH="${VIRTUAL_ENV}/lib:${LD_LIBRARY_PATH}"
        export C_INCLUDE_PATH="${VIRTUAL_ENV}/include:${C_INCLUDE_PATH}"
    else
        return 1
    fi
    if ! get_tests_deps; then
        return 1
    fi
    pushd "${jm_root}"
    if ! set_jm_cfg; then
        return 1
    fi
    if ! set_jm_datadir; then
        return 1
    fi
    run_jm_tests
    success="$?"
    tests_cleanup
    return ${success:-1}
}
main
