#!/usr/bin/env bash
# lan_sync.sh — folder sync between your own devices on a LAN
# via rsync over SSH, with neighbor auto-discovery (arp/avahi) and dry-run by default.
#
# The idea: if the devices can see each other on the LAN, there is no reason to
# route the same traffic through a cloud relay. Lower latency, no external
# dependency, nothing leaves the network.
#
# Usage:
#   ./lan_sync.sh discover                          # find live LAN neighbors
#   ./lan_sync.sh preview <host> <src> <dst>        # show the plan (rsync dry-run)
#   ./lan_sync.sh push    <host> <src> <dst>        # send src -> host:dst
#   ./lan_sync.sh pull    <host> <src> <dst>        # fetch host:src -> dst
#   ./lan_sync.sh mirror  <host> <src> <dst>        # exact mirror (--delete!)
#
# Options (environment variables):
#   LAN_SYNC_USER=starmynd   SSH user for neighbors
#   LAN_SYNC_PORT=22         SSH port
#   LAN_SYNC_EXCLUDE=".git,node_modules,.DS_Store"   comma-separated excludes
#
# Example:
#   LAN_SYNC_USER=alice ./lan_sync.sh push 192.168.1.50 ~/docs /home/alice/docs

set -euo pipefail

PROG="$(basename "$0")"
USER_DEFAULT="${LAN_SYNC_USER:-$USER}"
PORT_DEFAULT="${LAN_SYNC_PORT:-22}"
EXCLUDE_DEFAULT="${LAN_SYNC_EXCLUDE:-.git,node_modules,.DS_Store,.Trash-1000}"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | tail -n +2; exit "${1:-0}"; }
die()   { echo "Error: $*" >&2; exit 1; }

# --- neighbor discovery -------------------------------------------------------
cmd_discover() {
    local -a rows=()
    local ip name

    # 1) arp table: live entries (IP in parens: ? (192.168.1.5) at aa:bb...)
    while read -r ip; do
        [ -n "$ip" ] || continue
        rows+=("$ip|")
    done < <(arp -an 2>/dev/null | sed -n 's/.*(\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)).*/\1/p')

    # 2) avahi/bonjour: SSH-capable host names
    if command -v avahi-browse >/dev/null 2>&1; then
        while read -r name ip; do
            [ -n "$ip" ] || continue
            rows+=("$ip|$name")
        done < <(avahi-browse -rtd _ssh._tcp 2>/dev/null | awk -F';' '$1=="=" && $7=="IPv4" {print $4" "$8}')
    fi

    if [ "${#rows[@]}" -eq 0 ]; then
        echo "No neighbors found. Try pinging the subnet first, or pass an IP manually."
        return 0
    fi

    local shown
    shown="$(printf '%s\n' "${rows[@]}" | awk -F'|' '!seen[$1]++ { printf "  %-16s %s\n", $1, $2 }')"
    if [ -n "$shown" ]; then
        echo "Hosts found:"
        echo "$shown"
        echo "Total: $(printf '%s\n' "$shown" | grep -c .)"
    else
        echo "No neighbors found."
    fi
    echo
    echo "Next, e.g.:  $PROG preview <ip> ~/docs /home/${USER_DEFAULT}/docs"
}

# --- rsync plumbing -----------------------------------------------------------
build_excludes() { # -> NUL-separated --exclude parameters for rsync
    local IFS=','
    local items=() args=()
    read -ra items <<<"$EXCLUDE_DEFAULT" || true
    local it
    for it in "${items[@]}"; do
        [ -n "$it" ] && args+=("--exclude=$it")
    done
    [ ${#args[@]} -gt 0 ] && printf '%s\0' "${args[@]}"
    return 0
}

run_rsync() { # $1 mode(preview|push|pull|mirror) $2 host $3 src $4 dst
    local mode="$1" host="$2" src="$3" dst="$4"
    local -a remote_opts=("-e" "ssh -p $PORT_DEFAULT -o ConnectTimeout=5 -o BatchMode=yes")
    local -a flags=(-aH --info=stats1,progress2 --partial)
    [ "$mode" = "mirror" ] && flags+=(--delete)

    local -a excl=()
    while IFS= read -r -d '' arg; do excl+=("$arg"); done < <(build_excludes)
    set -- "${excl[@]+"${excl[@]}"}"   # empty exclude list is a valid case (bash 3.2 + set -u)

    if [ "$mode" = "preview" ]; then
        flags+=(--dry-run --itemize-changes)
        echo "DRY-RUN (nothing is copied). Plan $src -> ${host}:${dst}"
        echo "rsync ${flags[*]} $* ..."
    else
        echo "$mode $src <-> ${host}:..."
    fi

    case "$mode" in
        preview|push|mirror)
            rsync "${remote_opts[@]}" "${flags[@]}" "$@" "$src" "${USER_DEFAULT}@${host}:${dst}"
            ;;
        pull)
            rsync "${remote_opts[@]}" "${flags[@]}" "$@" "${USER_DEFAULT}@${host}:${src}" "$dst"
            ;;
    esac
}

cmd_preview() { run_rsync preview "$@"; }
cmd_push()    { run_rsync push    "$@"; }
cmd_pull()    { run_rsync pull    "$@"; }
cmd_mirror()  { echo "WARNING: mirror deletes extra files on the destination (--delete)."; run_rsync mirror "$@"; }

main() {
    [ $# -ge 1 ] || usage 1
    local cmd="$1"; shift
    case "$cmd" in
        discover) cmd_discover "$@" ;;
        preview)  [ $# -eq 3 ] || die "usage: $PROG preview <host> <src> <dst>"; cmd_preview "$@" ;;
        push)     [ $# -eq 3 ] || die "usage: $PROG push <host> <src> <dst>";    cmd_push "$@" ;;
        pull)     [ $# -eq 3 ] || die "usage: $PROG pull <host> <src> <dst>";    cmd_pull "$@" ;;
        mirror)   [ $# -eq 3 ] || die "usage: $PROG mirror <host> <src> <dst>";  cmd_mirror "$@" ;;
        -h|--help|help) usage 0 ;;
        *) die "unknown command: $cmd" ;;
    esac
}

main "$@"
