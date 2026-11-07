#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: duplicates.sh
# Purpose: Two-phase duplicate detector (size clustering -> SHA-256 hash verification)
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

DUPLICATES_REPORT_FILE="$PROJECT_ROOT/reports/duplicate_investigation.txt"

# ------------------------------------------------------------------------------
# Duplicate Detection Engine
# ------------------------------------------------------------------------------
run_duplicate_detector() {
    local target_roots="$1"

    local roots=()
    if [ -n "$target_roots" ] && [ "$target_roots" != "auto" ]; then
        # shellcheck disable=SC2206
        roots=($target_roots)
    else
        read -r -a roots <<< "$(select_scan_targets)"
    fi

    if [ ${#roots[@]} -eq 0 ]; then
        error "No valid targets selected."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "DUPLICATE FILE DETECTION (CRYPTOGRAPHIC INTEGRITY)"
    info "Investigating Targets: ${roots[*]}"
    info "Algorithm: Phase 1 (Size Clustering) -> Phase 2 (SHA-256 Hash Collision Verification)"
    warn "SAFETY NOTICE: Read-only investigation. No files will be modified or deleted."
    print_divider

    init_scan_log
    local start_time
    start_time=$(date +%s)

    local temp_sizes="$PROJECT_ROOT/data/tmp_dup_sizes.tsv"
    ensure_dir "$PROJECT_ROOT/data"
    : > "$temp_sizes"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    # Phase 1: Collect size and path for non-empty regular files
    search_status "Phase 1: Cataloging files and identifying matching byte sizes..."
    for r in "${roots[@]}"; do
        [ ! -d "$r" ] && continue
        if [ ${#prune_args[@]} -gt 0 ]; then
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                -type f -size +0c \
                -printf '%s\t%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_sizes"
        else
            find "$symlink_flag" "$r" \
                -type f -size +0c \
                -printf '%s\t%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_sizes"
        fi
    done

    local total_files_scanned
    total_files_scanned="$(wc -l < "$temp_sizes" | tr -d '[:space:]')"

    if [ "$total_files_scanned" -eq 0 ]; then
        warn "No non-empty files discovered in the selected target(s)."
        rm -f "$temp_sizes"
        press_enter_to_continue
        return 0
    fi

    info "Discovered $total_files_scanned candidate files. Filtering for size collisions..."

    # Identify duplicate sizes using awk
    local size_collisions="$PROJECT_ROOT/data/tmp_dup_size_collisions.tsv"
    awk -F'\t' '
        { count[$1]++; lines[$1] = (lines[$1] ? lines[$1] RS $2 : $2) }
        END {
            for (s in count) {
                if (count[s] > 1) {
                    split(lines[s], arr, RS)
                    for (i in arr) {
                        print s "\t" arr[i]
                    }
                }
            }
        }
    ' "$temp_sizes" > "$size_collisions"

    local candidate_count
    candidate_count="$(wc -l < "$size_collisions" | tr -d '[:space:]')"

    if [ "$candidate_count" -eq 0 ]; then
        success "Investigation complete: No files share matching sizes. Zero duplicates present!"
        rm -f "$temp_sizes" "$size_collisions"
        press_enter_to_continue
        return 0
    fi

    # Phase 2: Compute SHA-256 checksums only for size collision candidates
    info "Found $candidate_count files sharing identical sizes. Computing SHA-256 hashes..."
    local temp_hashes="$PROJECT_ROOT/data/tmp_dup_hashes.tsv"
    : > "$temp_hashes"

    local hashed_counter=0
    while IFS=$'\t' read -r fsize fpath || [ -n "$fpath" ]; do
        [ -z "$fpath" ] && continue
        hashed_counter=$((hashed_counter + 1))
        
        # Calculate SHA-256
        local fhash
        fhash="$(sha256sum "$fpath" 2>/dev/null | awk '{print $1}')"
        if [ -n "$fhash" ]; then
            printf "%s\t%s\t%s\n" "$fhash" "$fsize" "$fpath" >> "$temp_hashes"
        fi
        
        if [ $((hashed_counter % 20)) -eq 0 ]; then
            printf "\r%s[*] Hashed %d of %d candidates...%s" "$C_CYAN" "$hashed_counter" "$candidate_count" "$C_RESET"
        fi
    done < "$size_collisions"
    printf "\r%s[*] Completed SHA-256 hashing for all %d candidates.%s\n" "$C_GREEN" "$candidate_count" "$C_RESET"

    # Group by identical Hash
    local temp_grouped="$PROJECT_ROOT/data/tmp_dup_grouped.tsv"
    # Sort by Hash
    sort -t$'\t' -k1,1 "$temp_hashes" > "$temp_grouped"

    # Parse duplicate clusters
    local duplicate_groups=0
    local total_duplicate_files=0
    local total_wasted_bytes=0

    # Temporary storage for display and report
    local dup_display_cache="$PROJECT_ROOT/data/dup_display_cache.txt"
    : > "$dup_display_cache"

    local current_hash=""
    local current_size=0
    local group_files=()

    flush_duplicate_group() {
        local count=${#group_files[@]}
        if [ "$count" -gt 1 ]; then
            duplicate_groups=$((duplicate_groups + 1))
            total_duplicate_files=$((total_duplicate_files + count))
            local redundant_copies=$((count - 1))
            local group_wasted=$((redundant_copies * current_size))
            total_wasted_bytes=$((total_wasted_bytes + group_wasted))

            local h_size
            h_size="$(format_bytes "$current_size")"
            local h_wasted
            h_wasted="$(format_bytes "$group_wasted")"

            {
                printf "DUPLICATE GROUP %d\n" "$duplicate_groups"
                printf "File Size: %s (%s bytes) | Copies: %d | Redundant Waste: %s\n" "$h_size" "$current_size" "$count" "$h_wasted"
                printf "SHA-256: %s\n" "$current_hash"
                printf "Matching Files:\n"
                for gf in "${group_files[@]}"; do
                    local win_gf
                    win_gf="$(to_win_path "$gf")"
                    printf "  * %s\n" "$win_gf"
                done
                printf "\n"
            } >> "$dup_display_cache"
        fi
    }

    while IFS=$'\t' read -r fhash fsize fpath || [ -n "$fpath" ]; do
        [ -z "$fpath" ] && continue
        if [ "$fhash" = "$current_hash" ]; then
            group_files+=("$fpath")
        else
            flush_duplicate_group
            current_hash="$fhash"
            current_size="$fsize"
            group_files=("$fpath")
        fi
    done < "$temp_grouped"
    flush_duplicate_group

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # Cleanup temp data
    rm -f "$temp_sizes" "$size_collisions" "$temp_hashes" "$temp_grouped"

    # Display Results
    clear_screen
    print_banner
    print_header "DUPLICATE INVESTIGATION SUMMARY"
    
    local h_total_wasted
    h_total_wasted="$(format_bytes "$total_wasted_bytes")"

    printf "%sInvestigation Metrics:%s\n" "$C_BOLD" "$C_RESET"
    printf "  * Scanned Files:               %s%d%s\n" "$C_WHITE" "$total_files_scanned" "$C_RESET"
    printf "  * Duplicate Clusters:          %s%d%s\n" "$C_YELLOW" "$duplicate_groups" "$C_RESET"
    printf "  * Total Redundant Files:       %s%d%s\n" "$C_RED" "$total_duplicate_files" "$C_RESET"
    printf "  * Potential Reclaimable Space: %s%s%s (%s bytes)\n" "$C_GREEN" "$h_total_wasted" "$C_RESET" "$total_wasted_bytes"
    printf "  * Investigation Time:          %s%d second(s)%s\n" "$C_CYAN" "$elapsed" "$C_RESET"
    print_divider

    if [ "$duplicate_groups" -eq 0 ]; then
        success "Zero duplicate groups found. All candidate files are cryptographically unique."
        press_enter_to_continue
        return 0
    fi

    # Display first few groups
    printf "%s%sDiscovered Duplicate Groups (Preview):%s\n\n" "$C_CYAN" "$C_BOLD" "$C_RESET"
    head -n 45 "$dup_display_cache"
    local total_lines
    total_lines="$(wc -l < "$dup_display_cache")"
    if [ "$total_lines" -gt 45 ]; then
        printf "%s... [Additional groups truncated for display. Full details saved] ...%s\n\n" "$C_YELLOW" "$C_RESET"
    fi

    print_divider
    if [ ! -t 0 ] || [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        rm -f "$dup_display_cache"
        return 0
    fi
    printf "%sOptions:%s [E] Export Duplicate Report | [M] Return to Menu\n" "$C_BOLD" "$C_RESET"
    printf "Select option: "
    read -r dup_act
    if [ "${dup_act^^}" = "E" ]; then
        ensure_dir "$PROJECT_ROOT/reports"
        local rep_file="$PROJECT_ROOT/reports/DUPLICATES_REPORT_$(get_timestamp).txt"
        {
            echo "================================================================================"
            echo "WHERE IS IT - DUPLICATE FILE INVESTIGATION REPORT"
            echo "Timestamp: $(get_display_timestamp)"
            echo "Targets:   ${roots[*]}"
            echo "Duplicate Groups Found: $duplicate_groups"
            echo "Total Duplicate Files:  $total_duplicate_files"
            echo "Potential Reclaimable Storage: $h_total_wasted ($total_wasted_bytes bytes)"
            echo "================================================================================"
            echo ""
            cat "$dup_display_cache"
        } > "$rep_file"
        success "Duplicate investigation report exported to: $(to_win_path "$rep_file")"
        press_enter_to_continue
    fi
    rm -f "$dup_display_cache"
}
