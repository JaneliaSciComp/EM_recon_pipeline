#!/usr/bin/env bash

# ----------------------------------------------------------------------------
# Usage: 03_copy_google_dump.sh [--vm VM_NAME] [--pattern DUMP_PATTERN] [--dest LOCAL_DEST_DIR]
#
# Connects to a Google Cloud VM via gcloud compute ssh to interactively select
# one or more MongoDB dump directories, then copies the selected .bson.gz files
# to local storage via gcloud compute scp.
#
# Example DUMP_PATTERNS: 'par.*s70', 'match.*s115', 'align.*s90', 'ic2d.*s080'
#
# Dump directories on the VM have the pattern:
#   /mnt/disks/mongodb_dump_fs/dump/<location>/<stage>/<project>/<slab-group>/<db>

set -euo pipefail

BASE_DUMP_DIR="/mnt/disks/mongodb_dump_fs/dump"

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
VM_NAME="render-ws-mongodb-16c-64gb-aaa"
DUMP_PATTERN=""
PATTERN_IS_ARG=false
LOCAL_DEST_DIR="$(pwd)/mongodb_dumps"

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm)
            VM_NAME="${2:-}"
            shift 2
            ;;
--pattern)
            DUMP_PATTERN="${2:-}"
            PATTERN_IS_ARG=true
            shift 2
            ;;
        --dest)
            LOCAL_DEST_DIR="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 --vm VM_NAME [--pattern DUMP_PATTERN] [--dest LOCAL_DEST_DIR]"
            exit 1
            ;;
    esac
done


# ----------------------------------------------------------------------------
# Build gcloud ssh/scp argument arrays (optional flags)
# ----------------------------------------------------------------------------
GCLOUD_FLAGS=()
GCLOUD_FLAGS+=(--zone "us-east4-c")

# SSH tunables (parallel to SCP tunables defined later)
SSH_TIMEOUT=30    # seconds before a hung ssh command is killed and retried
MAX_SSH_ATTEMPTS=4  # total attempts per vm_exec call
SSH_RETRY_WAIT=5  # seconds to wait between attempts

# Run a command on the VM and capture stdout.
# Retries up to MAX_SSH_ATTEMPTS times if the command times out or fails.
vm_exec() {
    local CMD="$1"
    local SSH_EXIT
    for (( SSH_ATTEMPT=1; SSH_ATTEMPT<=MAX_SSH_ATTEMPTS; SSH_ATTEMPT++ )); do
        SSH_EXIT=0
        timeout "$SSH_TIMEOUT"             gcloud compute ssh "$VM_NAME" "${GCLOUD_FLAGS[@]}" --command="$CMD"             2>/dev/null || SSH_EXIT=$?

        if (( SSH_EXIT == 0 )); then
            return 0
        elif (( SSH_EXIT == 124 )); then
            echo "  vm_exec timed out after ${SSH_TIMEOUT}s (attempt ${SSH_ATTEMPT}/${MAX_SSH_ATTEMPTS})." >&2
        else
            echo "  vm_exec exited with code ${SSH_EXIT} (attempt ${SSH_ATTEMPT}/${MAX_SSH_ATTEMPTS})." >&2
        fi

        if (( SSH_ATTEMPT < MAX_SSH_ATTEMPTS )); then
            sleep "$SSH_RETRY_WAIT"
        fi
    done
    return "$SSH_EXIT"
}

# ----------------------------------------------------------------------------
# Verify connectivity early
# ----------------------------------------------------------------------------
echo "Verifying connection to VM '${VM_NAME}'..."
if ! vm_exec "true"; then
    echo "Error: Could not connect to VM '${VM_NAME}'. Check --vm."
    exit 1
fi
echo "Connected."

# ----------------------------------------------------------------------------
# List unique child directory names one level below a remote path.
# ----------------------------------------------------------------------------
remote_list_level() {
    local REMOTE_BASE="${1%/}"
    vm_exec "find \"${REMOTE_BASE}\" -mindepth 1 -maxdepth 1 -type d \
             | sed \"s|^${REMOTE_BASE}/||\" | sort"
}

# ----------------------------------------------------------------------------
# Display a numbered list and prompt for one or more selections.
# Prepends the option to select all. Sets SELECTED array to chosen items.
# Returns 0 if "all" was chosen, 1 otherwise.
# ----------------------------------------------------------------------------
pick_many() {
    local PROMPT="$1"; shift
    local ITEMS=("$@")
    printf "\n%s\n" "$PROMPT"
    for (( I=0; I<${#ITEMS[@]}; I++ )); do
        printf "%5d) %s\n" $(( I+1 )) "${ITEMS[$I]#"$BASE_DUMP_DIR/"}"
    done
    printf "\nEnter numbers separated by spaces or commas, or 'all'.\n"
    while true; do
        read -rp "Selection: " RAW
        RAW="${RAW//,/ }"
        if [[ "$RAW" == "all" ]]; then
            SELECTED=("${ITEMS[@]}"); return 0
        fi
        SELECTED=()
        local VALID=true
        for TOK in $RAW; do
            if [[ "$TOK" =~ ^[0-9]+$ ]] && (( TOK >= 1 && TOK <= ${#ITEMS[@]} )); then
                SELECTED+=("${ITEMS[$((TOK-1))]}")
            else
                echo "  Invalid entry '$TOK' — enter numbers between 1 and ${#ITEMS[@]}."
                VALID=false; break
            fi
        done
        $VALID && [[ ${#SELECTED[@]} -gt 0 ]] && return 1
        $VALID && echo "  No selection made — please choose at least one."
    done
}

# ----------------------------------------------------------------------------
# Build the list of matching remote dump directories
# ----------------------------------------------------------------------------
MATCHES=()

if $PATTERN_IS_ARG; then
    # Free-form substring match anywhere in the remote path
    echo "Searching for dump directories matching pattern '${DUMP_PATTERN}' on VM..."
    while IFS= read -r D; do [[ -n "$D" ]] && MATCHES+=("$D"); done < <(
        vm_exec "find \"${BASE_DUMP_DIR}\" -mindepth 5 -maxdepth 5 -type d \
                 | grep \"${DUMP_PATTERN}\" | sort"
    )
else
    # Interactive drill-down: LOCATION → STAGE → PROJECT → SLAB_GROUP → DB
    LEVELS=("LOCATION" "STAGE" "PROJECT" "SLAB_GROUP" "DB")
    PARTIAL_PATHS=("")
    GLOB_PATTERNS=()

    for (( LVL=0; LVL<${#LEVELS[@]}; LVL++ )); do
        LABEL="${LEVELS[$LVL]}"

        # Collect deduplicated children across all current partial paths
        CHILDREN=()
        while IFS= read -r U; do [[ -n "$U" ]] && CHILDREN+=("$U"); done < <(
            for P in "${PARTIAL_PATHS[@]}"; do
                remote_list_level "${BASE_DUMP_DIR}/${P}"
            done | sort -u
        )

        if [[ ${#CHILDREN[@]} -eq 0 ]]; then
            echo "No subdirectories found under current selection. Aborting."
            exit 1
        fi

        PICK_RESULT=0
        pick_many "Select one or more ${LABEL}s:" "${CHILDREN[@]}" || PICK_RESULT=$?
        if [[ "$PICK_RESULT" -eq 0 ]]; then
            # "all" chosen — append wildcards for remaining levels
            STARS=""
            for (( R=LVL; R<${#LEVELS[@]}; R++ )); do STARS="${STARS}*/"; done
            GLOB_PATTERNS=()
            for P in "${PARTIAL_PATHS[@]}"; do
                GLOB_PATTERNS+=("${BASE_DUMP_DIR}/${P}${STARS%/}")
            done
            break
        else
            # Fan out: extend each partial path with each selected child
            NEW_PATHS=()
            for P in "${PARTIAL_PATHS[@]}"; do
                for SEL in "${SELECTED[@]}"; do
                    CANDIDATE="${P}${SEL}"
                    # Verify the combination actually exists on the VM
                    if vm_exec "test -d \"${BASE_DUMP_DIR}/${CANDIDATE}\" && echo yes" \
                       | grep -q yes; then
                        NEW_PATHS+=("${CANDIDATE}/")
                    fi
                done
            done

            if [[ ${#NEW_PATHS[@]} -eq 0 ]]; then
                echo "No valid directories found for that selection. Aborting."
                exit 1
            fi
            PARTIAL_PATHS=("${NEW_PATHS[@]}")

            # Last level: exact paths — no wildcards needed
            if (( LVL == ${#LEVELS[@]} - 1 )); then
                GLOB_PATTERNS=()
                for P in "${PARTIAL_PATHS[@]}"; do
                    GLOB_PATTERNS+=("${BASE_DUMP_DIR}/${P%/}")
                done
            fi
        fi
    done

    # Expand glob patterns to concrete remote paths
    echo "Enumerating matching dump directories on VM..."
    while IFS= read -r D; do [[ -n "$D" ]] && MATCHES+=("$D"); done < <(
        for PAT in "${GLOB_PATTERNS[@]}"; do
            vm_exec "find \"${BASE_DUMP_DIR}\" -mindepth 5 -maxdepth 5 -type d -path \"${PAT}\""
        done | sort -u
    )
fi

if [[ ${#MATCHES[@]} -eq 0 ]]; then
    echo "No MongoDB dump directories found on VM."
    exit 1
fi

# ----------------------------------------------------------------------------
# Final confirmation: let the user pick from the resolved directory list
# ----------------------------------------------------------------------------
PICK_ALL=0
pick_many "Select one or more MongoDB dump directories to copy:" "${MATCHES[@]}" || PICK_ALL=$?

FINAL_DIRS=()
if (( PICK_ALL == 0 )); then
    FINAL_DIRS=("${MATCHES[@]}")
else
    FINAL_DIRS=("${SELECTED[@]}")
fi

printf "\nYou selected the following MongoDB dump directories:\n"
printf '  %s\n' "${FINAL_DIRS[@]}"

# ----------------------------------------------------------------------------
# Collect the .bson.gz files to copy
# ----------------------------------------------------------------------------
FILES_TO_COPY=()
for DUMP_DIR in "${FINAL_DIRS[@]}"; do
    while IFS= read -r F; do [[ -n "$F" ]] && FILES_TO_COPY+=("$F"); done < <(
        vm_exec "find \"${DUMP_DIR}\" -maxdepth 1 -name '*.bson.gz' | sort"
    )
done

if [[ ${#FILES_TO_COPY[@]} -eq 0 ]]; then
    echo "No .bson.gz files found in the selected directories."
    exit 1
fi

printf "\nFiles to be copied (%d total):\n" "${#FILES_TO_COPY[@]}"
printf '  %s\n' "${FILES_TO_COPY[@]}"

# ----------------------------------------------------------------------------
# Confirm before copying
# ----------------------------------------------------------------------------
printf "\nDestination: %s\n" "$LOCAL_DEST_DIR"
read -rp "Proceed with copy? [y/n]: " CONFIRM
case "$CONFIRM" in
    y|Y) ;;
    *) echo "Aborted."; exit 0 ;;
esac

mkdir -p "$LOCAL_DEST_DIR"

# ----------------------------------------------------------------------------
# Retry / timeout tunables
# ----------------------------------------------------------------------------
SCP_TIMEOUT=15    # seconds before a hung scp is killed and retried
MAX_SCP_ATTEMPTS=4  # total attempts per file
SCP_RETRY_WAIT=5  # seconds to wait between attempts

# ----------------------------------------------------------------------------
# Copy files, preserving the remote sub-path under BASE_DUMP_DIR
# so that e.g. google/01_match/.../match/file.bson.gz lands at
# $LOCAL_DEST_DIR/google/01_match/.../match/file.bson.gz
#
# Each file is attempted up to MAX_SCP_ATTEMPTS times. If timeout kills the
# transfer, the partial local file is removed before the next attempt.
# ----------------------------------------------------------------------------
COPY_ERRORS=0
for REMOTE_FILE in "${FILES_TO_COPY[@]}"; do
    # Relative path beneath BASE_DUMP_DIR
    REL_PATH="${REMOTE_FILE#"${BASE_DUMP_DIR}/"}"
    LOCAL_FILE="${LOCAL_DEST_DIR}/${REL_PATH}"
    LOCAL_DIR="$(dirname "$LOCAL_FILE")"

    mkdir -p "$LOCAL_DIR"

    SUCCESS=false
    for (( ATTEMPT=1; ATTEMPT<=MAX_SCP_ATTEMPTS; ATTEMPT++ )); do
        if (( ATTEMPT == 1 )); then
            echo "Copying ${REL_PATH} ..."
        else
            echo "  Retrying ${REL_PATH} (attempt ${ATTEMPT}/${MAX_SCP_ATTEMPTS}) ..."
            sleep "$SCP_RETRY_WAIT"
        fi

        # Remove any partial file left by a previous failed/timed-out attempt
        [[ -f "$LOCAL_FILE" ]] && rm -f "$LOCAL_FILE"

        TIMEOUT_EXIT=0
        timeout "$SCP_TIMEOUT" \
            gcloud compute scp \
                "${GCLOUD_FLAGS[@]}" \
                "${VM_NAME}:${REMOTE_FILE}" \
                "${LOCAL_FILE}" || TIMEOUT_EXIT=$?

        if (( TIMEOUT_EXIT == 0 )); then
            SUCCESS=true
            break
        elif (( TIMEOUT_EXIT == 124 )); then
            echo "  Timed out after ${SCP_TIMEOUT}s." >&2
        else
            echo "  scp exited with code ${TIMEOUT_EXIT}." >&2
        fi
    done

    if ! $SUCCESS; then
        echo "  Warning: failed to copy ${REL_PATH} after ${MAX_SCP_ATTEMPTS} attempt(s)." >&2
        [[ -f "$LOCAL_FILE" ]] && rm -f "$LOCAL_FILE"
        (( COPY_ERRORS++ )) || true
    fi
done

echo
if (( COPY_ERRORS == 0 )); then
    echo "All files copied successfully to: ${LOCAL_DEST_DIR}"
else
    echo "${COPY_ERRORS} file(s) failed to copy. See warnings above."
    exit 1
fi