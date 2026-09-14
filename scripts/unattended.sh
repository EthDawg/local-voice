#!/bin/bash
# Keep this file identical in the Workbench Voice and StageMark repositories.
set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: bash scripts/unattended.sh [--] command [argument ...]' \
        'Keep the Mac and display awake until the command exits.' \
        'For pipelines or shell syntax, pass bash -c followed by a quoted command.'
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --) shift ;;
esac

if [[ $# -eq 0 || -z "$1" ]]; then
    usage >&2
    exit 64
fi

caffeinate_path="$(type -P caffeinate || true)"
if [[ -z "$caffeinate_path" || ! -f "$caffeinate_path" || ! -x "$caffeinate_path" ]]; then
    printf '%s\n' 'Unattended testing requires macOS caffeinate; the command was not started.' >&2
    exit 69
fi

command_path="$(type -P -- "$1" || true)"
if [[ -z "$command_path" || ! -f "$command_path" || ! -x "$command_path" ]]; then
    printf 'Cannot run command: %s\n' "$1" >&2
    exit 127
fi
shift

# caffeinate releases its assertions when the command exits and preserves its
# exit status. exec avoids leaving a wrapper shell or a detached keep-awake job.
exec "$caffeinate_path" -di "$command_path" "$@"
