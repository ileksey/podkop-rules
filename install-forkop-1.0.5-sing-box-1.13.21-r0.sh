        SING_BOX_INSTALL_VARIANT=""
        msg "sing-box $SING_BOX_PINNED_VERSION is already installed; keeping it"
    else
        SING_BOX_INSTALL_VARIANT="pinned"
        if [ -n "$current_version" ]; then
            msg "Installed sing-box version is $current_version; will request exact version $SING_BOX_PINNED_VERSION"
        else
            msg "Will install exact sing-box version $SING_BOX_PINNED_VERSION"
        fi
    fi
}

install_selected_sing_box() {
    [ "$SING_BOX_INSTALL_VARIANT" = "pinned" ] || {
        msg "$(installer_text sing_box_skip_msg)"
        return 0
    }

    msg "Installing sing-box=$SING_BOX_PINNED_VERSION from configured OpenWrt package feeds"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk add --upgrade "sing-box=$SING_BOX_PINNED_VERSION" </dev/null ||
            fail "Could not install sing-box=$SING_BOX_PINNED_VERSION. Check whether this exact package version exists in the configured APK feeds for this device. No other version will be accepted."
    else
        opkg install --force-downgrade "sing-box=$SING_BOX_PINNED_VERSION" </dev/null ||
            fail "Could not install sing-box=$SING_BOX_PINNED_VERSION. Check whether this exact package version exists in the configured OPKG feeds for this device. No other version will be accepted."
    fi

    current_version="$(sing_box_installed_version)"
    [ "$current_version" = "$SING_BOX_PINNED_VERSION" ] ||
        fail "sing-box version verification failed: expected $SING_BOX_PINNED_VERSION, detected '${current_version:-not installed}'"
    msg "Verified sing-box version $current_version"
}

cleanup_legacy_installation() {
    state_file="$TMP_DIR/install-state.env"

    install_json_ucode installer-cleanup-legacy >"$state_file" ||
        fail "Failed to prepare the system before Forkop package installation"

    # shellcheck disable=SC1090
    . "$state_file"
}

detect_legacy_installation() {
    FORKOP_LEGACY_DETECTED=0
    LEGACY_CONFIG_BACKUP=""

    if ! pkg_is_installed "$LEGACY_BACKEND_PACKAGE"; then
        legacy_config_present=0
        for legacy_config_path in \
            "/etc/config/$LEGACY_BACKEND_PACKAGE" \
            "/etc/config/$LEGACY_CONFIG_PACKAGE_ALT"; do
            if [ -r "$legacy_config_path" ]; then
                legacy_config_present=1
                break
            fi
        done
        [ "$legacy_config_present" -eq 1 ] || return 0
    fi

    FORKOP_LEGACY_DETECTED=1
    for legacy_config_path in \
        "/etc/config/$LEGACY_BACKEND_PACKAGE" \
        "/etc/config/$LEGACY_CONFIG_PACKAGE_ALT"; do
        if [ -r "$legacy_config_path" ]; then
            LEGACY_CONFIG_BACKUP="$TMP_DIR/legacy-config.backup"
            cp "$legacy_config_path" "$LEGACY_CONFIG_BACKUP" ||
                fail "Failed to back up the legacy configuration"
            break
        fi
    done

    msg "Legacy installation detected; its packages will be removed and its configuration will be upgraded"
}

decide_i18n_installation() {
    luci_lang="$(get_luci_main_lang)"

    detect_installer_language

    if pkg_is_installed "luci-i18n-forkop-ru"; then
        FORKOP_I18N_REQUESTED=1
        msg "$(installer_text i18n_installed)"
        return 0
    fi

    if [ "$FORKOP_LEGACY_DETECTED" -eq 1 ] &&
        pkg_is_installed "luci-i18n-${LEGACY_BACKEND_PACKAGE}-ru"; then
        FORKOP_I18N_REQUESTED=1
        msg "$(installer_text i18n_installed)"
        return 0
    fi

    case "$luci_lang" in
        ru|ru_*|ru-*)
            FORKOP_I18N_REQUESTED=1
            INSTALLER_LANG="ru"
            msg "$(installer_text luci_ru)"
            return 0
            ;;
    esac

    if numbered_yes_no_prompt "$(installer_text i18n_prompt)"; then
        FORKOP_I18N_REQUESTED=1
        INSTALLER_LANG="ru"
        return 0
    fi

    warn "$(installer_text i18n_skip)"
}

download_forkop_packages() {
    FORKOP_BACKEND_FILE="$TMP_DIR/$FORKOP_BACKEND_NAME"
    FORKOP_APP_FILE="$TMP_DIR/$FORKOP_APP_NAME"
    FORKOP_I18N_FILE=""

    download_with_retry "$FORKOP_BACKEND_URL" "$FORKOP_BACKEND_FILE" "$FORKOP_BACKEND_NAME" || fail "Failed to download $FORKOP_BACKEND_NAME"
    download_with_retry "$FORKOP_APP_URL" "$FORKOP_APP_FILE" "$FORKOP_APP_NAME" || fail "Failed to download $FORKOP_APP_NAME"

    if [ -n "$FORKOP_I18N_URL" ]; then
        FORKOP_I18N_FILE="$TMP_DIR/$FORKOP_I18N_NAME"
        download_with_retry "$FORKOP_I18N_URL" "$FORKOP_I18N_FILE" "$FORKOP_I18N_NAME" || fail "Failed to download $FORKOP_I18N_NAME"
    fi
}

install_backend_package() {
    pkg_install_files "$FORKOP_BACKEND_FILE" || fail "forkop installation failed"
}

migrate_legacy_configuration() {
    [ "$FORKOP_LEGACY_DETECTED" -eq 1 ] || return 0

    if [ -n "$LEGACY_CONFIG_BACKUP" ]; then
        cp "$LEGACY_CONFIG_BACKUP" /etc/config/forkop ||
            fail "Failed to restore the legacy configuration for migration"
        chmod 0644 /etc/config/forkop ||
            fail "Failed to set permissions on the Forkop configuration"

        msg "Migrating the legacy configuration to Forkop"
        if ! FORKOP_CONFIG_NAME="forkop" \
            FORKOP_LIB="/usr/lib/forkop" \
            ucode -L /usr/lib/forkop /usr/lib/forkop/config/migration.uc migrate-podkop; then
            cp "$LEGACY_CONFIG_BACKUP" /etc/config/forkop 2>/dev/null || true
            fail "Legacy configuration migration failed; the original configuration was restored"
        fi
    else
        warn "The legacy package had no readable configuration; Forkop defaults will be used"
    fi

    install_json_ucode installer-finalize-legacy ||
        fail "Failed to remove legacy configuration and cache files after migration"
}

install_ui_packages() {
    pkg_install_files "$FORKOP_APP_FILE" || fail "luci-app-forkop installation failed"

    if [ -n "$FORKOP_I18N_FILE" ]; then
        pkg_install_files "$FORKOP_I18N_FILE" || fail "luci-i18n-forkop-ru installation failed"
    fi
}

post_install() {
    FORKOP_WAS_ENABLED="$FORKOP_WAS_ENABLED" FORKOP_WAS_RUNNING="$FORKOP_WAS_RUNNING" \
        install_json_ucode installer-post-install ||
        fail "Failed to complete Forkop post-install actions"
}

main() {
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    parse_args "$@"
    check_root
    init_tmp_dir
    detect_fetcher
    sync_time
    check_system

    detect_legacy_installation
    decide_i18n_installation
    select_sing_box_installation

    pkg_list_update || fail "Failed to update package lists"
    ensure_bootstrap_ucode_runtime

    resolve_forkop_release
    download_forkop_packages

    cleanup_legacy_installation
    install_backend_package
