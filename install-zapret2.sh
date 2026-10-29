#!/bin/sh
# Separate bootstrap installer for the official bol-van/zapret2 on OpenWrt.
# It does not install or modify Forkop / sing-box directly.

set -u

REPO_URL="https://github.com/bol-van/zapret2/archive/refs/heads/master.tar.gz"
TMP_BASE="/tmp/zapret2-bootstrap.$$"
ARCHIVE="$TMP_BASE/zapret2.tar.gz"
SRC_DIR="$TMP_BASE/source"

say() { printf '%s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_BASE"; }
trap cleanup EXIT HUP INT TERM

[ "$(id -u 2>/dev/null)" = "0" ] || fail "Запусти скрипт от root (например, через SSH под root)."
[ -r /etc/openwrt_release ] || fail "Скрипт рассчитан на OpenWrt; /etc/openwrt_release не найден."

if ! command -v wget >/dev/null 2>&1; then
    fail "Не найден wget. Установи его через менеджер пакетов OpenWrt и повтори запуск."
fi
if ! command -v tar >/dev/null 2>&1; then
    fail "Не найден tar. Установи его через менеджер пакетов OpenWrt и повтори запуск."
fi

say "============================================================"
say " Установка официального bol-van/zapret2 для OpenWrt"
say "============================================================"
say "Будет скачан текущий исходный код из официального GitHub-репозитория."
say "Далее запустится штатный install_easy.sh проекта."
say "По умолчанию штатный установщик использует каталог /opt/zapret2."
say ""
say "ВАЖНО: установка zapret2 может менять правила firewall и параметры flow offloading."
say "На роутере уже используется Forkop/Sing-box; совместимость правил заранее не гарантируется."
say "Скрипт не удаляет Forkop и Sing-box, но после установки нужно проверить маршрутизацию и доступ в интернет."
say ""
printf 'Продолжить? [y/N]: '
read answer
case "$answer" in
    y|Y|yes|YES|д|Д|да|ДА) ;;
    *) say "Отменено пользователем."; exit 0 ;;
esac

mkdir -p "$TMP_BASE" "$SRC_DIR" || fail "Не удалось создать временный каталог $TMP_BASE"
say ""
say "Скачивание исходников zapret2..."
wget -O "$ARCHIVE" "$REPO_URL" || fail "Не удалось скачать архив. Проверь интернет-доступ и DNS на роутере."
[ -s "$ARCHIVE" ] || fail "Скачанный архив пуст."

say "Распаковка..."
tar -xzf "$ARCHIVE" -C "$SRC_DIR" || fail "Не удалось распаковать архив (нужна поддержка gzip в tar)."

INSTALLER="$(find "$SRC_DIR" -type f -name install_easy.sh 2>/dev/null | head -n 1)"
[ -n "$INSTALLER" ] && [ -f "$INSTALLER" ] || fail "В архиве не найден официальный install_easy.sh."

say ""
say "Запуск штатного установщика zapret2."
say "Отвечай на его вопросы внимательно; если он предлагает заменить существующий /opt/zapret2, не соглашайся, если там уже есть нужная установка."
say "------------------------------------------------------------"
cd "$(dirname "$INSTALLER")" || fail "Не удалось перейти в каталог исходников."
sh "$INSTALLER"
RC=$?
if [ "$RC" -ne 0 ]; then
    fail "Штатный установщик завершился с кодом $RC. Вывод выше содержит причину."
fi

say ""
say "Штатный установщик завершился без ошибки."
say "Проверь состояние службы командой: /opt/zapret2/init.d/openwrt/zapret2 status"
say "Если команда не найдена, проверь каталог установки /opt/zapret2."
exit 0
