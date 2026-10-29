#!/bin/sh
# Universal installer for bol-van/zapret2 packaged for OpenWrt 25.12+ (APK).
# Uses published OpenWrt APK packages from 1andrevich/zapret2-openwrt because
# the upstream source archive does not provide router-native binaries for every target.
# Does not build software on the router and does not directly edit Forkop/sing-box config.

set -eu

RELEASE_BASE='https://github.com/1andrevich/zapret2-openwrt/releases/latest/download'
KEY_NAME='zapret2-1andrevich.pub'
KEY_URL="$RELEASE_BASE/$KEY_NAME"
TMP_DIR="/tmp/zapret2-installer.$$"

say() { printf '%s\n' "$*"; }
fail() { say "ОШИБКА: $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

[ "$(id -u 2>/dev/null || echo 1)" = 0 ] || fail 'Запусти скрипт от root.'
[ -r /etc/openwrt_release ] || fail 'Это не OpenWrt: /etc/openwrt_release не найден.'
command -v wget >/dev/null 2>&1 || fail 'Не найден wget.'
command -v apk >/dev/null 2>&1 || fail 'Не найден apk. Этот установщик предназначен для OpenWrt 25.12+ с APK.'
[ -e /lib/apk/db/installed ] || fail 'Не найдена база APK (/lib/apk/db/installed). Отказ от установки, чтобы не перепутать менеджеры пакетов.'

OPENWRT_ARCH="$(sed -n 's/^OPENWRT_ARCH=//p' /etc/os-release 2>/dev/null | head -n 1 | tr -d "\"'")"
[ -n "$OPENWRT_ARCH" ] || fail 'Не удалось определить OPENWRT_ARCH из /etc/os-release.'

say '============================================================'
say ' Установка zapret2 для OpenWrt 25.12+ (APK)'
say '============================================================'
say "Архитектура пакета: $OPENWRT_ARCH"
say 'Используется готовый пакет bol-van/zapret2, собранный для OpenWrt.'
say 'Это позволяет избежать ошибки upstream-установщика «build tools not found». '
say ''
say 'ВНИМАНИЕ: установка может добавить/изменить правила firewall.'
say 'Forkop/Sing-box не удаляются, но совместимость маршрутизации не гарантируется.'
say 'Первое подтверждение пропущено для совместимости с запуском wget | sh.'
say ''

mkdir -p "$TMP_DIR" || fail 'Не удалось создать временный каталог.'
CORE_APK="$TMP_DIR/zapret2.apk"
LUCI_APK="$TMP_DIR/luci-app-zapret2.apk"
KEY_FILE="$TMP_DIR/$KEY_NAME"
KEY_DEST="/etc/apk/keys/$KEY_NAME"

say 'Скачивание ключа подписи пакетов...'
wget -q -O "$KEY_FILE" "$KEY_URL" || fail 'Не удалось скачать ключ подписи.'
[ -s "$KEY_FILE" ] || fail 'Файл ключа пуст.'
mkdir -p /etc/apk/keys || fail 'Не удалось создать /etc/apk/keys.'
if [ -f "$KEY_DEST" ]; then
    say "Ключ уже существует: $KEY_DEST (не перезаписываю)."
else
    cp "$KEY_FILE" "$KEY_DEST" || fail 'Не удалось установить ключ подписи.'
    chmod 644 "$KEY_DEST" 2>/dev/null || true
fi

say 'Скачивание zapret2 для определённой архитектуры...'
wget -O "$CORE_APK" "$RELEASE_BASE/zapret2_${OPENWRT_ARCH}.apk" || fail "Для архитектуры '$OPENWRT_ARCH' не удалось скачать пакет. Возможно, она пока не поддерживается опубликованными сборками."
[ -s "$CORE_APK" ] || fail 'Скачанный пакет zapret2 пуст.'

INSTALL_LUCI=0
if [ -f /www/cgi-bin/luci ] || [ -d /www/luci-static ]; then
    say 'Обнаружен LuCI; дополнительно устанавливаю интерфейс управления.'
    wget -O "$LUCI_APK" "$RELEASE_BASE/luci-app-zapret2.apk" || fail 'Не удалось скачать luci-app-zapret2.apk.'
    [ -s "$LUCI_APK" ] || fail 'Скачанный пакет LuCI пуст.'
    INSTALL_LUCI=1
else
    say 'LuCI не обнаружен; будет установлен только пакет zapret2.'
fi

# If an unmanaged /opt/zapret2 exists, preserve it by moving it aside.
# This commonly happens when upstream install_easy.sh extracted sources and then
# stopped at "build tools not found". Never delete the directory automatically.
BACKUP_DIR=''
if [ -d /opt/zapret2 ] && ! apk info -e zapret2 >/dev/null 2>&1; then
    STAMP="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo unknown)"
    BACKUP_DIR="/opt/zapret2.backup-$STAMP-$$"
    say "Найден /opt/zapret2, не зарегистрированный в APK."
    say "Чтобы сохранить прежние файлы и освободить путь для пакета, перемещаю каталог в: $BACKUP_DIR"
    mv /opt/zapret2 "$BACKUP_DIR" || fail 'Не удалось сохранить существующий /opt/zapret2. Установка остановлена.'
fi

say ''
say 'Установка пакетов через APK (подпись проверяется менеджером пакетов)...'
if [ "$INSTALL_LUCI" -eq 1 ]; then
    if ! apk add "$CORE_APK" "$LUCI_APK"; then
        say 'ОШИБКА: APK не смог установить пакеты. Forkop/Sing-box не удалялись намеренно.' >&2
        [ -z "$BACKUP_DIR" ] || say "Сохранённый прежний каталог: $BACKUP_DIR" >&2
        exit 1
    fi
else
    if ! apk add "$CORE_APK"; then
        say 'ОШИБКА: APK не смог установить пакет zapret2.' >&2
        [ -z "$BACKUP_DIR" ] || say "Сохранённый прежний каталог: $BACKUP_DIR" >&2
        exit 1
    fi
fi

say ''
say 'Установка пакетов завершена.'
say 'Проверь статус службы и настройки в LuCI → Службы → Zapret2 (если LuCI установлен).'
say 'После установки проверь доступ в интернет и работу правил Forkop/Sing-box.'
