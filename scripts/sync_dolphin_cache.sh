#!/bin/bash
set -Eeuo pipefail

USER_NAME=${SUDO_USER:-$(id -un)}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$USER_HOME" ] || { echo "ERRO: nao foi possivel determinar o HOME de '$USER_NAME'." >&2; exit 1; }

RAM_CACHE="${DOLPHIN_RAM_CACHE:-$USER_HOME/.var/app/org.DolphinEmu.dolphin-emu/cache/dolphin-emu}"
SD_BACKUP="${DOLPHIN_SHADER_BACKUP:-$USER_HOME/dolphin_shader_backup}"
LOCK_DIR="$USER_HOME/.cache/dolphin-boost"
LOCK_FILE="$LOCK_DIR/cache.lock"

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

require_cmds() {
    local cmd
    for cmd in flock mountpoint pgrep rsync; do
        command -v "$cmd" > /dev/null 2>&1 || die "comando obrigatorio ausente: $cmd"
    done
}

prepare_lock() {
    mkdir -p "$LOCK_DIR"
    touch "$LOCK_FILE"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "outra sincronizacao/execucao do Dolphin Turbo ja esta em andamento."
}

dolphin_running() {
    pgrep -u "$USER_NAME" -f 'org\.DolphinEmu\.dolphin-emu|dolphin-emu' > /dev/null 2>&1
}

dir_has_entries() {
    [ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

ensure_dirs() {
    mkdir -p "$RAM_CACHE" "$SD_BACKUP"
}

sync_start() {
    if dolphin_running; then
        die "Dolphin esta em execucao; feche-o antes de carregar o cache."
    fi

    if ! mountpoint -q "$RAM_CACHE"; then
        log "AVISO: $RAM_CACHE nao esta montado em RAM; a copia seguira no armazenamento atual."
    fi

    log "Carregando shaders..."
    rsync -a --info=progress2 "$SD_BACKUP/" "$RAM_CACHE/"
}

sync_stop() {
    if dolphin_running && [ "${FORCE_SYNC:-0}" != "1" ]; then
        die "Dolphin esta em execucao; feche-o antes de salvar o cache."
    fi

    if ! dir_has_entries "$RAM_CACHE" && dir_has_entries "$SD_BACKUP"; then
        die "cache atual vazio; abortando para nao apagar o backup existente."
    fi

    log "Salvando shaders..."
    rsync -a --info=progress2 --delete "$RAM_CACHE/" "$SD_BACKUP/"
}

status_cache() {
    if mountpoint -q "$RAM_CACHE"; then
        log "Cache: montado em RAM ($RAM_CACHE)"
    else
        log "Cache: nao montado em RAM ($RAM_CACHE)"
    fi

    if dolphin_running; then
        log "Dolphin: em execucao"
    else
        log "Dolphin: parado"
    fi
}

main() {
    require_cmds
    prepare_lock
    ensure_dirs

    case "${1:-}" in
        start)
            sync_start
            ;;
        stop)
            sync_stop
            ;;
        status)
            status_cache
            ;;
        *)
            echo "Uso: $0 {start|stop|status}" >&2
            exit 2
            ;;
    esac
}

main "$@"
