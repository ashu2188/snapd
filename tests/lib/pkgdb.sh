#!/bin/bash

# shellcheck source=tests/lib/quiet.sh
. "$TESTSLIB/quiet.sh"

debian_name_package() {
    case "$1" in
        xdelta3|curl|python3-yaml|kpartx|busybox-static)
            echo "$1"
            ;;
        man)
            echo "man-db"
            ;;
        *)
            echo $1
            ;;
    esac
}

fedora_name_package() {
    case "$1" in
        xdelta3|jq|curl|python3-yaml)
            echo $1
            ;;
        openvswitch-switch)
            echo "openvswitch"
            ;;
        printer-driver-cups-pdf)
            echo "cups-pdf"
            ;;
        *)
            echo $1
            ;;
    esac
}

opensuse_name_package() {
    case "$1" in
        *)
            echo $1
            ;;
    esac
}

distro_name_package() {
    case "$SPREAD_SYSTEM" in
        ubuntu-*|debian-*)
            debian_name_package "$1"
            ;;
        fedora-*)
            fedora_name_package "$1"
            ;;
        opensuse-*)
            opensuse_name_package "$1"
            ;;
        *)
            echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
            exit 1
            ;;
    esac
}

distro_install_local_package() {
    allow_downgrades=false
    while [ -n "$1" ]; do
        case "$1" in
            --allow-downgrades)
                allow_downgrades=true
                shift
                ;;
            *)
                break
        esac
    done

    case "$SPREAD_SYSTEM" in
        ubuntu-14.04-*|debian-*)
            # relying on dpkg as apt(-get) does not support installation from local files in trusty.
            dpkg -i --force-depends --auto-deconfigure --force-depends-version "$@"
            apt-get -f install -y
            ;;
        ubuntu-*)
            flags="-y"
            if [ "$allow_downgrades" = "true" ]; then
                flags="$flags --allow-downgrades"
            fi
            # shellcheck disable=SC2086
            apt install $flags "$@"
            ;;
        fedora-*)
            dnf -q -y install "$@"
            ;;
        opensuse-*)
            zypper -q install -y "$@"
            ;;
        *)
            echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
            exit 1
            ;;
    esac
}

distro_install_package() {
    for pkg in "$@" ; do
        package_name=$(distro_name_package "$pkg")
        # When we could not find a different package name for the distribution
        # we're running on we try the package name given as last attempt
        if [ -z "$package_name" ]; then
            package_name="$pkg"
        fi

        case "$SPREAD_SYSTEM" in
            ubuntu-*|debian-*)
                quiet apt-get install -y "$package_name"
                ;;
            fedora-*)
                dnf -q -y install -y $package_name
                ;;
            opensuse-*)
                zypper -q install -y $package_name
                ;;
            *)
                echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
                exit 1
                ;;
        esac
    done
}

distro_purge_package() {
    for pkg in "$@" ; do
        package_name=$(distro_name_package "$pkg")
        # When we could not find a different package name for the distribution
        # we're running on we try the package name given as last attempt
        if [ -z "$package_name" ]; then
            package_name="$pkg"
        fi

        case "$SPREAD_SYSTEM" in
            ubuntu-*|debian-*)
                quiet apt-get remove -y --purge -y "$package_name"
                ;;
            fedora-*)
                dnf -y -q remove $package_name
                ;;
            opensuse-*)
                zypper -q remove -y $package_name
                ;;
            *)
                echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
                exit 1
                ;;
        esac
    done
}

distro_update_package_db() {
    case "$SPREAD_SYSTEM" in
        ubuntu-*|debian-*)
            quiet apt-get update
            ;;
        fedora-*)
            dnf -y -q upgrade
            ;;
        opensuse-*)
            zypper -q update -y
            ;;
        *)
            echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
            exit 1
            ;;
    esac
}

distro_clean_package_cache() {
    case "$SPREAD_SYSTEM" in
        ubuntu-*|debian-*)
            quiet apt-get clean
            ;;
        opensuse-*)
            zypper -q clean --all
            ;;
        *)
            echo "ERROR: Unsupported distribution $SPREAD_SYSTEM"
            exit 1
            ;;
    esac
}

distro_auto_remove_packages() {
    case "$SPREAD_SYSTEM" in
        ubuntu-*|debian-*)
            quiet apt-get -y autoremove
            ;;
        fedora-*)
            dnf -q -y autoremove
            ;;
        opensuse-*)
            ;;
        *)
            echo "ERROR: Unsupported distribution '$SPREAD_SYSTEM'"
            exit 1
            ;;
    esac
}

distro_query_package_info() {
    case "$SPREAD_SYSTEM" in
        ubuntu-*|debian-*)
            apt-cache policy "$1"
            ;;
        fedora-*)
            dnf info "$1"
            ;;
        opensuse-*)
            zypper info "$1"
            ;;
    esac
}

distro_install_build_snapd(){
    if [ "$SRU_VALIDATION" = "1" ]; then
        apt install -y snapd
        cp /etc/apt/sources.list sources.list.back
        echo "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -c -s)-proposed restricted main multiverse universe" | tee /etc/apt/sources.list -a
        apt update
        apt install -y --only-upgrade snapd
        mv sources.list.back /etc/apt/sources.list
        apt update
    else
        packages=
        case "$SPREAD_SYSTEM" in
            ubuntu-*|debian-*)
                packages="${GOHOME}/snapd_*.deb"
                ;;
            fedora-*)
                packages="${GOHOME}/snap-confine*.rpm ${GOPATH}/snapd*.rpm"
                ;;
            opensuse-*)
                packages="${GOHOME}/snapd*.rpm"
                ;;
            *)
                exit 1
                ;;
        esac

        distro_install_local_package $packages

        # On some distributions the snapd.socket is not yet automatically
        # enabled as we don't have a systemd present configuration approved
        # by the distribution for it in place yet.
        if ! systemctl is-enabled snapd.socket ; then
            sudo systemctl enable --now snapd.socket
        fi
    fi
}

# Specify necessary packages which need to be installed on a
# system to provide a basic build environment for snapd.
export DISTRO_BUILD_DEPS=()
case "$SPREAD_SYSTEM" in
    debian-*|ubuntu-*)
        DISTRO_BUILD_DEPS=(build-essential curl devscripts expect gdebi-core jq rng-tools git netcat-openbsd)
        ;;
    fedora-*)
        DISTRO_BUILD_DEPS=(mock git expect curl golang rpm-build redhat-lsb-core)
        ;;
    opensuse-*)
        DISTRO_BUILD_DEPS=(osc git expect curl golang-packaging lsb-release netcat-openbsd jq rng-tools)
        ;;
    *)
        ;;
esac
