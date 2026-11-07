#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: indexer.sh
# Purpose: High-speed local filesystem indexing, search, refresh & staleness tracking
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
    # shellcheck source=src/scanner.sh
    source "$SCRIPT_DIR/scanner.sh"
    # shellcheck source=src/search.sh
    source "$SCRIPT_DIR/search.sh"
fi

INDEX_DIR="$PROJECT_ROOT/index"
INDEX_DB="$INDEX_DIR/fs_index.db"
INDEX_META="$INDEX_DIR/fs_index.meta"

# ------------------------------------------------------------------------------
# Manage Search Index Menu (Feature 9)
# ------------------------------------------------------------------------------
manage_index_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "SEARCH INDEX MANAGER"
        printf "A local filesystem index enables instantaneous searches across large drives.\n"
        printf "%sNotice: Indexed data reflects a snapshot in time; remember to refresh after file changes.%s\n\n" "$C_YELLOW" "$C_RESET"

        # Check index state
        if [ -f "$INDEX_DB" ] && [ -f "$INDEX_META" ]; then
            local meta_date meta_roots meta_files meta_dirs meta_bytes
            # shellcheck source=/dev/null
            source "$INDEX_META"
            local idx_size
            idx_size="$(wc -c < "$INDEX_DB" 2>/dev/null | tr -d '[:space:]')"
            local h_idx_size
            h_idx_size="$(format_bytes "$idx_size")"
            local h_indexed_bytes
            h_indexed_bytes="$(format_bytes "$meta_bytes")"

            printf "%sCurrent Index Status: %sACTIVE%s\n" "$C_BOLD" "$C_GREEN" "$C_RESET"
            printf "  * Built On:         %s%s%s\n" "$C_WHITE" "$meta_date" "$C_RESET"
            printf "  * Indexed Targets:  %s%s%s\n" "$C_WHITE" "$meta_roots" "$C_RESET"
            printf "  * Total Entries:    %s%d files, %d folders%s (%s indexed)\n" "$C_CYAN" "$meta_files" "$meta_dirs" "$C_RESET" "$h_indexed_bytes"
            printf "  * Index File Size:  %s%s%s\n" "$C_YELLOW" "$h_idx_size" "$C_RESET"
        else
            printf "%sCurrent Index Status: %sNOT INITIALIZED%s\n" "$C_BOLD" "$C_GRAY" "$C_RESET"
            printf "  * No persistent index found. Searches currently scan live storage.\n"
        fi
        print_divider

        printf "  %s1.%s Search Using Fast Index\n" "$C_CYAN" "$C_RESET"
        printf "  %s2.%s Build / Create Search Index\n" "$C_CYAN" "$C_RESET"
        printf "  %s3.%s Refresh / Rebuild Index\n" "$C_CYAN" "$C_RESET"
        printf "  %s4.%s View Detailed Index Statistics\n" "$C_CYAN" "$C_RESET"
        printf "  %s5.%s Delete Existing Index\n" "$C_CYAN" "$C_RESET"
        print_divider
        printf "  %s0.%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect option [0-5]: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "$choice" in
            1) search_index_interactive ;;
            2|3) build_search_index ;;
            4) show_index_statistics ;;
            5) delete_search_index ;;
            0) break ;;
            *) warn "Invalid selection." ; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Build / Create Index
# ------------------------------------------------------------------------------
build_search_index() {
    clear_screen
    print_banner
    print_header "BUILDING LOCAL SEARCH INDEX"

    read -r -a roots <<< "$(select_scan_targets)"
    if [ ${#roots[@]} -eq 0 ]; then
        error "No targets selected for indexing."
        press_enter_to_continue
        return 1
    fi

    info "Indexing Targets: ${roots[*]}"
    info "Traversing directory hierarchy and writing persistent index..."
    ensure_dir "$INDEX_DIR"
    
    local temp_index="$INDEX_DIR/tmp_fs_index.db"
    : > "$temp_index"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    local start_time
    start_time=$(date +%s)

    for r in "${roots[@]}"; do
        [ ! -d "$r" ] && continue
        search_status "Indexing drive root: $r"
        if [ ${#prune_args[@]} -gt 0 ]; then
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                -printf '%y\t%s\t%T@\t%f\t%p\n' 2>/dev/null >> "$temp_index"
        else
            find "$symlink_flag" "$r" \
                -printf '%y\t%s\t%T@\t%f\t%p\n' 2>/dev/null >> "$temp_index"
        fi
    done

    # Atomic move
    mv -f "$temp_index" "$INDEX_DB"

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # Count statistics
    local total_files total_dirs total_bytes
    total_files="$(awk -F'\t' '$1 == "f" {count++} END {print count+0}' "$INDEX_DB")"
    total_dirs="$(awk -F'\t' '$1 == "d" {count++} END {print count+0}' "$INDEX_DB")"
    total_bytes="$(awk -F'\t' '$1 == "f" {sum += $2} END {print sum+0}' "$INDEX_DB")"

    # Write metadata
    cat > "$INDEX_META" << EOF
meta_date="$(get_display_timestamp)"
meta_epoch="$end_time"
meta_roots="${roots[*]}"
meta_files="$total_files"
meta_dirs="$total_dirs"
meta_bytes="$total_bytes"
EOF

    success "Search index built successfully in $elapsed second(s)!"
    printf "  * Indexed %d files and %d directories.\n" "$total_files" "$total_dirs"
    printf "  * Total storage indexed: %s\n" "$(format_bytes "$total_bytes")"
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Search The Index
# ------------------------------------------------------------------------------
search_index_interactive() {
    if [ ! -f "$INDEX_DB" ]; then
        warn "Index does not exist yet. Please build the index first (Option 2)."
        press_enter_to_continue
        return 1
    fi

    clear_screen
    print_banner
    print_header "FAST INDEX SEARCH"
    printf "Search across previously indexed drives with zero disk recursion delay.\n\n"

    printf "Enter keyword to search in index: "
    read -r keyword
    if [ -z "$keyword" ]; then
        warn "Keyword cannot be empty."
        press_enter_to_continue
        return 1
    fi

    local start_time
    start_time=$(date +%s)

    local temp_raw="$PROJECT_ROOT/data/tmp_idx_search.tsv"
    ensure_dir "$PROJECT_ROOT/data"

    # Fast grep on filename (column 4) or path (column 5)
    # Using awk for case-insensitive matching
    local kw_lower="${keyword,,}"
    awk -F'\t' -v kw="$kw_lower" '
        tolower($4) ~ kw {
            print $2 "|" $3 "|" $1 "|" $5
        }
    ' "$INDEX_DB" > "$temp_raw"

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # Populate LAST_RESULTS_FILE using search.sh ranking logic
    : > "$LAST_RESULTS_FILE"
    local count=0
    local file_count=0
    local folder_count=0

    while IFS='|' read -r r_size r_mtime r_type r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        count=$((count + 1))
        [ "$r_type" = "f" ] && file_count=$((file_count + 1))
        [ "$r_type" = "d" ] && folder_count=$((folder_count + 1))

        local bname
        bname="$(basename "$r_path")"
        local bname_lower="${bname,,}"
        local rank=3
        if [ "$bname_lower" = "$kw_lower" ]; then
            [ "$r_type" = "f" ] && rank=1 || rank=2
        fi

        local mtime_int="${r_mtime%.*}"
        local ext=""
        [ "$r_type" = "f" ] && ext="$(get_file_extension "$bname")" || ext="[DIR]"
        local win_path
        win_path="$(to_win_path "$r_path")"

        if [ "$count" -le "$CFG_MAX_RESULTS" ]; then
            printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$count" "$rank" "$r_type" "$bname" "$ext" "$r_size" "$mtime_int" "$win_path" "$r_path" >> "$LAST_RESULTS_FILE"
        fi
    done < "$temp_raw"
    rm -f "$temp_raw"

    display_search_results "Index:$keyword" "$count" "$file_count" "$folder_count" "$elapsed"
}

# ------------------------------------------------------------------------------
# View Index Statistics
# ------------------------------------------------------------------------------
show_index_statistics() {
    clear_screen
    print_banner
    print_header "SEARCH INDEX DETAILED METRICS"

    if [ ! -f "$INDEX_DB" ] || [ ! -f "$INDEX_META" ]; then
        warn "Index has not been built yet."
        press_enter_to_continue
        return 0
    fi

    local meta_date meta_epoch meta_roots meta_files meta_dirs meta_bytes
    # shellcheck source=/dev/null
    source "$INDEX_META"

    local current_epoch
    current_epoch=$(date +%s)
    local age_seconds=$(( current_epoch - meta_epoch ))
    local age_hours=$(( age_seconds / 3600 ))

    local db_bytes
    db_bytes="$(wc -c < "$INDEX_DB" | tr -d '[:space:]')"

    printf "  * Index Location:       %s\n" "$(to_win_path "$INDEX_DB")"
    printf "  * Metadata Location:    %s\n" "$(to_win_path "$INDEX_META")"
    printf "  * Creation Timestamp:   %s\n" "$meta_date"
    printf "  * Index Age:            %d hour(s) ago\n" "$age_hours"
    printf "  * Target Roots Indexed: %s\n" "$meta_roots"
    printf "  * Total Indexed Files:  %d\n" "$meta_files"
    printf "  * Total Indexed Dirs:   %d\n" "$meta_dirs"
    printf "  * Total Storage Volume: %s\n" "$(format_bytes "$meta_bytes")"
    printf "  * Index Database Size:  %s (%s bytes)\n" "$(format_bytes "$db_bytes")" "$db_bytes"
    print_divider

    if [ "$age_hours" -ge 24 ]; then
        warn "Staleness Warning: The index is over $age_hours hours old. Files may have changed; consider refreshing."
    else
        success "Index is fresh (built within the last 24 hours)."
    fi

    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# Delete Index
# ------------------------------------------------------------------------------
delete_search_index() {
    if [ ! -f "$INDEX_DB" ] && [ ! -f "$INDEX_META" ]; then
        info "No active index to delete."
        sleep 1
        return 0
    fi

    if prompt_confirm "Are you sure you want to delete the search index database?" "N"; then
        rm -f "$INDEX_DB" "$INDEX_META"
        success "Search index and metadata deleted."
    else
        info "Deletion cancelled."
    fi
    sleep 1
}
