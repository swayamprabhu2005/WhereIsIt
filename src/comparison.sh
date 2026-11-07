#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: comparison.sh
# Purpose: Investigation snapshot comparison (detect new, missing, modified & moved files)
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
    # shellcheck source=src/scanner.sh
    source "$SCRIPT_DIR/scanner.sh"
fi

SNAPSHOT_DIR="$PROJECT_ROOT/data/snapshots"

# ------------------------------------------------------------------------------
# Snapshot & Comparison Menu
# ------------------------------------------------------------------------------
comparison_menu() {
    ensure_dir "$SNAPSHOT_DIR"

    while true; do
        clear_screen
        print_banner
        print_header "INVESTIGATION SNAPSHOT COMPARISON"
        printf "Capture and compare filesystem states to trace newly introduced, deleted, modified, or relocated files.\n\n"

        printf "  %s1.%s Create New State Snapshot\n" "$C_CYAN" "$C_RESET"
        printf "  %s2.%s Compare Two Existing Snapshots\n" "$C_CYAN" "$C_RESET"
        printf "  %s3.%s List Stored Snapshots\n" "$C_CYAN" "$C_RESET"
        printf "  %s4.%s Delete a Snapshot\n" "$C_CYAN" "$C_RESET"
        print_divider
        printf "  %s0.%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect option [0-4]: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "$choice" in
            1) create_snapshot_interactive ;;
            2) compare_snapshots_interactive ;;
            3) list_snapshots ;;
            4) delete_snapshot_interactive ;;
            0) break ;;
            *) warn "Invalid selection." ; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Create Snapshot
# ------------------------------------------------------------------------------
create_snapshot_interactive() {
    clear_screen
    print_banner
    print_header "CAPTURE INVESTIGATION SNAPSHOT"

    read -r -a roots <<< "$(select_scan_targets)"
    if [ ${#roots[@]} -eq 0 ]; then
        error "No targets selected."
        press_enter_to_continue
        return 1
    fi

    printf "Enter a label for this snapshot (e.g. Before_Install, Baseline_C): "
    read -r snap_label
    snap_label="$(echo "$snap_label" | sed 's/[^a-zA-Z0-9_-]/_/g')"
    [ -z "$snap_label" ] && snap_label="Snapshot"

    local snap_file="$SNAPSHOT_DIR/${snap_label}_$(get_timestamp).snap"

    info "Capturing snapshot across: ${roots[*]}"
    info "Recording file sizes, timestamps, and SHA-256 signatures..."

    local temp_snap="$SNAPSHOT_DIR/tmp.snap"
    : > "$temp_snap"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    local start_time
    start_time=$(date +%s)

    for r in "${roots[@]}"; do
        [ ! -d "$r" ] && continue
        if [ ${#prune_args[@]} -gt 0 ]; then
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                -type f -printf '%p\t%s\t%T@\n' 2>/dev/null >> "$temp_snap"
        else
            find "$symlink_flag" "$r" \
                -type f -printf '%p\t%s\t%T@\n' 2>/dev/null >> "$temp_snap"
        fi
    done

    # Calculate SHA-256 hashes for cataloged files
    local total_files
    total_files="$(wc -l < "$temp_snap" | tr -d '[:space:]')"

    info "Cataloged $total_files files. Generating cryptographic signatures..."
    : > "$snap_file"

    local counter=0
    while IFS=$'\t' read -r fpath fsize fmtime || [ -n "$fpath" ]; do
        [ -z "$fpath" ] && continue
        counter=$((counter + 1))

        local fhash
        fhash="$(sha256sum "$fpath" 2>/dev/null | awk '{print $1}')"
        [ -z "$fhash" ] && fhash="NO_HASH"

        local m_int="${fmtime%.*}"
        local win_path
        win_path="$(to_win_path "$fpath")"

        # Format: POSIX_PATH \t WIN_PATH \t SIZE \t MTIME_EPOCH \t SHA256
        printf "%s\t%s\t%s\t%s\t%s\n" \
            "$fpath" "$win_path" "$fsize" "$m_int" "$fhash" >> "$snap_file"

        if [ $((counter % 50)) -eq 0 ]; then
            printf "\r%s[*] Processed %d of %d files...%s" "$C_CYAN" "$counter" "$total_files" "$C_RESET"
        fi
    done < "$temp_snap"
    rm -f "$temp_snap"

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    printf "\r"
    success "Snapshot successfully captured in $elapsed second(s)!"
    printf "  * Saved as: %s\n" "$(to_win_path "$snap_file")"
    printf "  * Recorded %d file states.\n" "$total_files"
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Compare Snapshots
# ------------------------------------------------------------------------------
compare_snapshots_interactive() {
    clear_screen
    print_banner
    print_header "COMPARE TWO INVESTIGATION SNAPSHOTS"

    local snapshots=("$SNAPSHOT_DIR"/*.snap)
    if [ ! -e "${snapshots[0]}" ]; then
        warn "No snapshots found in $SNAPSHOT_DIR. Please create snapshots first."
        press_enter_to_continue
        return 1
    fi

    printf "Available Snapshots:\n"
    local idx=0
    for s in "${snapshots[@]}"; do
        idx=$((idx + 1))
        local sname
        sname="$(basename "$s")"
        local scount
        scount="$(wc -l < "$s" | tr -d '[:space:]')"
        printf "  %s%d.%s %-40s (%d records)\n" "$C_CYAN" "$idx" "$C_RESET" "$sname" "$scount"
    done
    print_divider

    if [ "$idx" -lt 2 ]; then
        warn "You need at least two snapshots to perform a comparison."
        press_enter_to_continue
        return 1
    fi

    printf "Select Baseline Snapshot (Older) [1-%d]: " "$idx"
    read -r sel1
    printf "Select Comparison Snapshot (Newer) [1-%d]: " "$idx"
    read -r sel2

    if ! [[ "$sel1" =~ ^[0-9]+$ ]] || ! [[ "$sel2" =~ ^[0-9]+$ ]] || [ "$sel1" -lt 1 ] || [ "$sel1" -gt "$idx" ] || [ "$sel2" -lt 1 ] || [ "$sel2" -gt "$idx" ]; then
        error "Invalid selection."
        press_enter_to_continue
        return 1
    fi

    local snap1="${snapshots[$((sel1 - 1))]}"
    local snap2="${snapshots[$((sel2 - 1))]}"

    info "Comparing Baseline: $(basename "$snap1")"
    info "Against:            $(basename "$snap2")"

    # Analysis data structures using temporary files
    local new_files="$PROJECT_ROOT/data/tmp_cmp_new.tsv"
    local missing_files="$PROJECT_ROOT/data/tmp_cmp_missing.tsv"
    local modified_files="$PROJECT_ROOT/data/tmp_cmp_modified.tsv"
    local moved_files="$PROJECT_ROOT/data/tmp_cmp_moved.tsv"

    : > "$new_files"
    : > "$missing_files"
    : > "$modified_files"
    : > "$moved_files"

    # Use awk associative arrays to compare
    awk -F'\t' '
        FILENAME == ARGV[1] {
            # Snap 1: Baseline
            snap1_path[$1] = 1
            snap1_size[$1] = $3
            snap1_mtime[$1] = $4
            snap1_hash[$1] = $5
            snap1_win[$1] = $2
            if ($5 != "NO_HASH") {
                hash_to_path1[$5] = $1
                hash_to_win1[$5] = $2
            }
            next
        }
        FILENAME == ARGV[2] {
            # Snap 2: Current / Follow-up
            snap2_path[$1] = 1
            snap2_size[$1] = $3
            snap2_mtime[$1] = $4
            snap2_hash[$1] = $5
            snap2_win[$1] = $2
            if ($5 != "NO_HASH") {
                hash_to_path2[$5] = $1
                hash_to_win2[$5] = $2
            }

            if (!($1 in snap1_path)) {
                # Candidate new file
                # Check if hash existed in snap1 at another path (Moved file!)
                if ($5 != "NO_HASH" && ($5 in hash_to_path1)) {
                    print $2 "\t" hash_to_win1[$5] "\t" $5 >> "'"$moved_files"'"
                } else {
                    print $2 "\t" $3 "\t" $5 >> "'"$new_files"'"
                }
            } else {
                # Existed in both. Check modified
                if (snap1_size[$1] != $3 || (snap1_hash[$1] != $5 && $5 != "NO_HASH")) {
                    print $2 "\t" snap1_size[$1] "\t" $3 "\t" snap1_hash[$1] "\t" $5 >> "'"$modified_files"'"
                }
            }
            next
        }
        END {
            # Check for missing files (in snap1 but not in snap2)
            for (p in snap1_path) {
                if (!(p in snap2_path)) {
                    # If hash is in snap2 at different path, it was already counted as moved
                    h = snap1_hash[p]
                    if (h == "NO_HASH" || !(h in hash_to_path2)) {
                        print snap1_win[p] "\t" snap1_size[p] "\t" h >> "'"$missing_files"'"
                    }
                }
            }
        }
    ' "$snap1" "$snap2"

    local c_new c_missing c_mod c_moved
    c_new="$(wc -l < "$new_files" | tr -d '[:space:]')"
    c_missing="$(wc -l < "$missing_files" | tr -d '[:space:]')"
    c_mod="$(wc -l < "$modified_files" | tr -d '[:space:]')"
    c_moved="$(wc -l < "$moved_files" | tr -d '[:space:]')"

    clear_screen
    print_banner
    print_header "COMPARISON AUDIT REPORT"
    printf "Baseline:   %s\n" "$(basename "$snap1")"
    printf "Comparison: %s\n\n" "$(basename "$snap2")"

    printf "  * %sNewly Discovered Files:%s       %s%d%s\n" "$C_GREEN" "$C_RESET" "$C_GREEN" "$c_new" "$C_RESET"
    printf "  * %sMissing / Deleted Files:%s      %s%d%s\n" "$C_RED" "$C_RESET" "$C_RED" "$c_missing" "$C_RESET"
    printf "  * %sModified Files (Size/Hash):%s   %s%d%s\n" "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$c_mod" "$C_RESET"
    printf "  * %sPotentially Relocated Files:%s  %s%d%s (Verified by SHA-256 match)\n" "$C_PURPLE" "$C_RESET" "$C_PURPLE" "$c_moved" "$C_RESET"
    print_divider

    if [ "$c_new" -gt 0 ]; then
        printf "%s[+] NEWLY DISCOVERED FILES (Top 10):%s\n" "$C_GREEN" "$C_RESET"
        head -n 10 "$new_files" | while IFS=$'\t' read -r wpath sz hsh; do
            printf "    %s (%s)\n" "$wpath" "$(format_bytes "$sz")"
        done
        printf "\n"
    fi

    if [ "$c_missing" -gt 0 ]; then
        printf "%s[-] MISSING / DELETED FILES (Top 10):%s\n" "$C_RED" "$C_RESET"
        head -n 10 "$missing_files" | while IFS=$'\t' read -r wpath sz hsh; do
            printf "    %s (%s)\n" "$wpath" "$(format_bytes "$sz")"
        done
        printf "\n"
    fi

    if [ "$c_mod" -gt 0 ]; then
        printf "%s[*] MODIFIED FILES (Top 10):%s\n" "$C_YELLOW" "$C_RESET"
        head -n 10 "$modified_files" | while IFS=$'\t' read -r wpath old_sz new_sz old_h new_h; do
            printf "    %s (Size: %s -> %s)\n" "$wpath" "$(format_bytes "$old_sz")" "$(format_bytes "$new_sz")"
        done
        printf "\n"
    fi

    if [ "$c_moved" -gt 0 ]; then
        printf "%s[>] RELOCATED / MOVED FILES (Verified Hash Match):%s\n" "$C_PURPLE" "$C_RESET"
        head -n 10 "$moved_files" | while IFS=$'\t' read -r new_p old_p hsh; do
            printf "    New: %s\n    Old: %s\n" "$new_p" "$old_p"
        done
        printf "\n"
    fi

    # Cleanup temp comparison files
    rm -f "$new_files" "$missing_files" "$modified_files" "$moved_files"

    print_divider
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# List Snapshots
# ------------------------------------------------------------------------------
list_snapshots() {
    clear_screen
    print_banner
    print_header "STORED INVESTIGATION SNAPSHOTS"

    local snapshots=("$SNAPSHOT_DIR"/*.snap)
    if [ ! -e "${snapshots[0]}" ]; then
        info "No stored snapshots."
        press_enter_to_continue
        return 0
    fi

    printf "%s%-40s %-12s %s%s\n" "$C_BOLD$C_BLUE" "Snapshot Filename" "Records" "File Size" "$C_RESET"
    print_divider

    for s in "${snapshots[@]}"; do
        local sname
        sname="$(basename "$s")"
        local count
        count="$(wc -l < "$s" | tr -d '[:space:]')"
        local sz
        sz="$(wc -c < "$s" | tr -d '[:space:]')"
        printf "%-40s %-12d %s\n" "$sname" "$count" "$(format_bytes "$sz")"
    done
    print_divider
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Delete Snapshot
# ------------------------------------------------------------------------------
delete_snapshot_interactive() {
    local snapshots=("$SNAPSHOT_DIR"/*.snap)
    if [ ! -e "${snapshots[0]}" ]; then
        info "No snapshots to delete."
        sleep 1
        return 0
    fi

    printf "Select Snapshot Number to delete:\n"
    local idx=0
    for s in "${snapshots[@]}"; do
        idx=$((idx + 1))
        printf "  %d. %s\n" "$idx" "$(basename "$s")"
    done
    printf "Choice [1-%d]: " "$idx"
    read -r del_idx

    if [[ "$del_idx" =~ ^[0-9]+$ ]] && [ "$del_idx" -ge 1 ] && [ "$del_idx" -le "$idx" ]; then
        local target_snap="${snapshots[$((del_idx - 1))]}"
        if prompt_confirm "Delete snapshot $(basename "$target_snap")?" "N"; then
            rm -f "$target_snap"
            success "Snapshot deleted."
        fi
    fi
    sleep 1
}
