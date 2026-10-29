#!/bin/sh
# shellcheck shell=dash

REPO_OWNER="ushan0v"
REPO_NAME="forkop"
# Deliberately pinned versions: do not follow the latest GitHub release/feed version.
FORKOP_PINNED_VERSION="1.0.5"
SING_BOX_PINNED_VERSION="1.13.21-r1"

REQUIRED_SPACE_KB=15360
CONNECT_TIMEOUT_SECONDS=15
METADATA_TIMEOUT_SECONDS=60
DOWNLOAD_TIMEOUT_SECONDS=600

PKG_IS_APK=0
FETCHER=""
TMP_DIR=""
FORKOP_WAS_ENABLED=0
FORKOP_WAS_RUNNING=0
FORKOP_LEGACY_DETECTED=0
FORKOP_I18N_REQUESTED=0
INSTALLER_LANG="en"
SING_BOX_INSTALL_VARIANT=""

FORKOP_RELEASE_JSON=""
FORKOP_RELEASE_TAG=""
FORKOP_BACKEND_URL=""
FORKOP_BACKEND_NAME=""
FORKOP_BACKEND_FILE=""
FORKOP_APP_URL=""
FORKOP_APP_NAME=""
FORKOP_APP_FILE=""
FORKOP_I18N_URL=""
FORKOP_I18N_NAME=""
FORKOP_I18N_FILE=""
FORKOP_PACKAGE_VERSION=""
LEGACY_BRAND="$(printf '\160\157\144\153\157\160')"
LEGACY_BACKEND_PACKAGE="${LEGACY_BRAND}-plus"
LEGACY_CONFIG_PACKAGE_ALT="${LEGACY_BRAND}_plus"
LEGACY_CONFIG_BACKUP=""

command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

msg() {
    printf '\033[32;1m%s\033[0m\n' "$1"
}

warn() {
    printf '\033[33;1m%s\033[0m\n' "$1"
}

fail() {
    printf '\033[31;1m%s\033[0m\n' "$1" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0

Installs pinned Forkop packages (version 1.0.5) and sing-box (version 1.13.21-r1):
  - forkop
  - luci-app-forkop
  - luci-i18n-forkop-ru when requested or when LuCI language is Russian

Can also install or switch sing-box variant:
  - stable sing-box from OpenWrt feeds
  - sing-box-extended from GitHub OpenWrt packages (for xHTTP support)
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown installer option: $1"
                ;;
        esac
        shift
    done
}

cleanup() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}

read_openwrt_release_value() {
    key="$1"

    [ -f /etc/openwrt_release ] || return 0
    sed -n "s/^${key}='\(.*\)'/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

init_tmp_dir() {
    TMP_DIR="$(mktemp -d /tmp/forkop.XXXXXX 2>/dev/null || true)"

    if [ -z "$TMP_DIR" ]; then
        TMP_DIR="/tmp/forkop.$$"
        mkdir -p "$TMP_DIR" || fail "Failed to create temporary directory: $TMP_DIR"
    fi
}

detect_fetcher() {
    if command_exists wget; then
        FETCHER="wget"
        return 0
    fi

    if command_exists curl; then
        FETCHER="curl"
        return 0
    fi

    fail "wget or curl is required to download Forkop"
}

run_with_deadline() {
    forkop_deadline_seconds="$1"
    shift
