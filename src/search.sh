#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: search.sh
# Purpose: Core search engine, multi-drive execution, result ranking & inspection menu
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

LAST_RESULTS_FILE="$PROJECT_ROOT/data/last_search_results.tsv"

# ------------------------------------------------------------------------------
# Core Search Logic
# ------------------------------------------------------------------------------
# Arguments:
# $1: keyword
# $2: search_type ("all", "file", "folder")
# $3: exact_match (0 or 1)
# $4: target_roots (space-separated paths, or "auto" for interactive / default)
run_search() {
    local keyword="$1"
    local search_type="${2:-all}" # all, file, folder
    local exact_match="${3:-0}"
    local target_roots="$4"
    local include_hidden="${5:-1}"

    if [ -z "$keyword" ]; then
        error "Search keyword cannot be empty."
        return 1
    fi

    # Determine scan roots
    local roots=()
    if [ -n "$target_roots" ] && [ "$target_roots" != "auto" ]; then
        # shellcheck disable=SC2206
        roots=($target_roots)
    else
        read -r -a roots <<< "$(select_scan_targets)"
    fi

    if [ ${#roots[@]} -eq 0 ]; then
        error "No valid search targets selected."
        return 1
    fi

    clear_screen
    print_banner
    print_header "SEARCH IN PROGRESS"
    info "Keyword:        $C_YELLOW$keyword$C_RESET"
    info "Target Roots:   $C_CYAN${roots[*]}$C_RESET"
    info "Search Type:    $C_WHITE${search_type^^}$C_RESET"
    info "Exact Match:    $([ "$exact_match" = "1" ] && echo "${C_GREEN}Yes" || echo "${C_GRAY}No (Partial)")$C_RESET"
    info "Case Sensitive: $([ "$CFG_CASE_SENSITIVE" = "1" ] && echo "${C_GREEN}Yes" || echo "${C_GRAY}No")$C_RESET"
    info "Max Results:    $C_YELLOW$CFG_MAX_RESULTS$C_RESET"
    print_divider

    init_scan_log
    local start_time
    start_time=$(date +%s)

    local temp_raw="$PROJECT_ROOT/data/tmp_search_raw.txt"
    ensure_dir "$PROJECT_ROOT/data"
    : > "$temp_raw"

    # Build find search pattern
    local name_pattern
    if [ "$exact_match" = "1" ]; then
        name_pattern="$keyword"
    else
        name_pattern="*${keyword}*"
    fi

    local name_flag="-iname"
    [ "$CFG_CASE_SENSITIVE" = "1" ] && name_flag="-name"

    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    # Type flag
    local type_filter=()
    case "$search_type" in
        file)   type_filter=("-type" "f") ;;
        folder) type_filter=("-type" "d") ;;
        all)    type_filter=() ;;
    esac

    # Prune arguments
    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    info "Scanning directories... (Please wait)"
    local current_root_idx=0
    local total_roots=${#roots[@]}

    for r in "${roots[@]}"; do
        current_root_idx=$((current_root_idx + 1))
        search_status "[$current_root_idx/$total_roots] Investigating target: $r"

        if [ ! -d "$r" ]; then
            warn "Target path $r is not accessible. Skipping."
            continue
        fi

        # Execute safe find with -printf '%s|%T@|%y|%p\n'
        # %s = size, %T@ = epoch mtime, %y = type (f/d), %p = full path
        if [ ${#prune_args[@]} -gt 0 ]; then
            # shellcheck disable=SC2086
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                "${type_filter[@]}" "$name_flag" "$name_pattern" \
                -printf '%s|%T@|%y|%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        else
            find "$symlink_flag" "$r" \
                "${type_filter[@]}" "$name_flag" "$name_pattern" \
                -printf '%s|%T@|%y|%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        fi
    done

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # --------------------------------------------------------------------------
    # Process & Rank Results (Enhancement C)
    # --------------------------------------------------------------------------
    # Rank 1: Exact filename match (f)
    # Rank 2: Exact folder-name match (d)
    # Rank 3: Partial filename match (f)
    # Rank 4: Partial folder-name match (d)
    # Rank 5: Other
    local temp_ranked="$PROJECT_ROOT/data/tmp_ranked.tsv"
    : > "$temp_ranked"

    local kw_lower="${keyword,,}"

    while IFS='|' read -r r_size r_mtime r_type r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        
        # Hidden file filter
        local bname
        bname="$(basename "$r_path")"
        if [ "$include_hidden" = "0" ] && [[ "$bname" =~ ^\. ]]; then
            continue
        fi

        local bname_lower="${bname,,}"
        local rank=5
        if [ "$r_type" = "f" ]; then
            if [ "$bname_lower" = "$kw_lower" ]; then
                rank=1
            else
                rank=3
            fi
        elif [ "$r_type" = "d" ]; then
            if [ "$bname_lower" = "$kw_lower" ]; then
                rank=2
            else
                rank=4
            fi
        fi

        # Epoch mtime integer conversion
        local mtime_int
        mtime_int="${r_mtime%.*}"
        [ -z "$mtime_int" ] && mtime_int=0

        # Extension
        local ext=""
        if [ "$r_type" = "f" ]; then
            ext="$(get_file_extension "$bname")"
        else
            ext="[DIR]"
        fi

        # Windows Path
        local win_path
        win_path="$(to_win_path "$r_path")"

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$rank" "$r_type" "$bname" "$ext" "$r_size" "$mtime_int" "$win_path" "$r_path" >> "$temp_ranked"
    done < "$temp_raw"

    # Sort results by Rank ascending, then Name ascending
    local sorted_ranked="$PROJECT_ROOT/data/tmp_sorted.tsv"
    sort -t$'\t' -k1,1n -k3,3 "$temp_ranked" 2>/dev/null > "$sorted_ranked"

    # Cap at CFG_MAX_RESULTS and assign 1-based index
    : > "$LAST_RESULTS_FILE"
    local count=0
    local file_count=0
    local folder_count=0

    while IFS=$'\t' read -r rank r_type bname ext r_size mtime_int win_path r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        count=$((count + 1))
        [ "$r_type" = "f" ] && file_count=$((file_count + 1))
        [ "$r_type" = "d" ] && folder_count=$((folder_count + 1))

        if [ "$count" -le "$CFG_MAX_RESULTS" ]; then
            printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$count" "$rank" "$r_type" "$bname" "$ext" "$r_size" "$mtime_int" "$win_path" "$r_path" >> "$LAST_RESULTS_FILE"
        fi
    done < "$sorted_ranked"

    # Clean up temp files
    rm -f "$temp_raw" "$temp_ranked" "$sorted_ranked"

    # Record search into history (Feature 8)
    if [ -f "$PROJECT_ROOT/src/history.sh" ]; then
        # shellcheck source=src/history.sh
        source "$PROJECT_ROOT/src/history.sh"
        record_search_history "$keyword" "${roots[*]}" "$search_type" "$count"
    fi

    # Display results
    display_search_results "$keyword" "$count" "$file_count" "$folder_count" "$elapsed"
}

# ------------------------------------------------------------------------------
# Display & Interactive Results View
# ------------------------------------------------------------------------------
display_search_results() {
    local keyword="$1"
    local total_count="$2"
    local file_count="$3"
    local folder_count="$4"
    local elapsed="$5"
    local err_count
    err_count="$(get_scan_error_count)"

    clear_screen
    print_banner
    print_header "INVESTIGATION RESULTS: '$keyword'"
    
    printf "%sSummary:%s %s%d%s matching items found (%s%d files%s, %s%d folders%s) in %s%d second(s)%s.\n" \
        "$C_BOLD" "$C_RESET" "$C_GREEN" "$total_count" "$C_RESET" \
        "$C_CYAN" "$file_count" "$C_RESET" "$C_YELLOW" "$folder_count" "$C_RESET" \
        "$C_WHITE" "$elapsed" "$C_RESET"
    if [ "$err_count" -gt 0 ]; then
        printf "%sInaccessible locations / permission denied:%s %s%d paths logged%s\n" \
            "$C_YELLOW" "$C_RESET" "$C_RED" "$err_count" "$C_RESET"
    fi
    print_divider

    if [ "$total_count" -eq 0 ]; then
        info "No matching files or folders discovered."
        press_enter_to_continue
        return 0
    fi

    # Table Header
    printf "%s%-5s %-5s %-6s %-10s %-20s %s%s\n" \
        "$C_BOLD$C_BLUE" "No." "Type" "Rank" "Size" "Modified Date" "Discovered Path" "$C_RESET"
    print_divider

    local display_limit=$CFG_MAX_RESULTS
    local shown=0

    while IFS=$'\t' read -r idx rank r_type bname ext r_size mtime_int win_path r_path || [ -n "$r_path" ]; do
        [ -z "$r_path" ] && continue
        shown=$((shown + 1))
        
        local type_badge="[FILE]"
        local type_color="$C_CYAN"
        if [ "$r_type" = "d" ]; then
            type_badge="[DIR] "
            type_color="$C_YELLOW"
        fi

        local rank_badge="P-Match"
        if [ "$rank" = "1" ]; then
            rank_badge="EX-FILE"
        elif [ "$rank" = "2" ]; then
            rank_badge="EX-DIR "
        fi

        local h_size
        if [ "$r_type" = "f" ]; then
            h_size="$(format_bytes "$r_size")"
        else
            h_size="---"
        fi

        local h_date
        h_date="$(format_epoch "$mtime_int")"

        printf "%s%-5d%s %s%-5s%s %s%-6s%s %-10s %-20s %s%s%s\n" \
            "$C_GRAY" "$idx" "$C_RESET" \
            "$type_color" "$type_badge" "$C_RESET" \
            "$C_PURPLE" "$rank_badge" "$C_RESET" \
            "$h_size" "$h_date" \
            "$C_WHITE" "$win_path" "$C_RESET"

        if [ "$shown" -ge 40 ]; then
            printf "%s... [Showing first 40 of %d matches. Full list saved in memory/reports] ...%s\n" "$C_YELLOW" "$total_count" "$C_RESET"
            break
        fi
    done < "$LAST_RESULTS_FILE"

    print_divider
    if [ ! -t 0 ] || [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        return 0
    fi
    results_action_menu "$keyword"
}

# ------------------------------------------------------------------------------
# Post-Search Interactive Action Menu
# ------------------------------------------------------------------------------
results_action_menu() {
    local keyword="$1"

    while true; do
        printf "\n%sAvailable Actions:%s\n" "$C_BOLD" "$C_RESET"
        printf "  %s[1-%s]%s Inspect Metadata of item number\n" "$C_CYAN" "$CFG_MAX_RESULTS" "$C_RESET"
        printf "  %s[E]%s   Export Investigation Report (TXT or CSV)\n" "$C_CYAN" "$C_RESET"
        printf "  %s[T]%s   View Timeline of Discovered Items\n" "$C_CYAN" "$C_RESET"
        printf "  %s[B]%s   Bookmark an Item\n" "$C_CYAN" "$C_RESET"
        printf "  %s[S]%s   Check for Suspicious Indicators\n" "$C_CYAN" "$C_RESET"
        printf "  %s[M]%s   Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect an action: %s" "$C_WHITE" "$C_RESET"
        read -r action
        action="$(echo "$action" | tr -d '[:space:]')"

        case "${action^^}" in
            M|"")
                break
                ;;
            E)
                if [ -f "$PROJECT_ROOT/src/reporter.sh" ]; then
                    # shellcheck source=src/reporter.sh
                    source "$PROJECT_ROOT/src/reporter.sh"
                    export_report_menu "$keyword" "$LAST_RESULTS_FILE"
                else
                    error "Reporter module not available."
                fi
                ;;
            T)
                if [ -f "$PROJECT_ROOT/src/timeline.sh" ]; then
                    # shellcheck source=src/timeline.sh
                    source "$PROJECT_ROOT/src/timeline.sh"
                    display_timeline_from_results "$LAST_RESULTS_FILE" "$keyword"
                else
                    error "Timeline module not available."
                fi
                ;;
            B)
                printf "Enter item number [1-%s] to bookmark: " "$CFG_MAX_RESULTS"
                read -r b_num
                if [[ "$b_num" =~ ^[0-9]+$ ]]; then
                    local target_line
                    target_line="$(awk -F'\t' -v n="$b_num" '$1 == n {print $0}' "$LAST_RESULTS_FILE")"
                    if [ -n "$target_line" ]; then
                        local ppath
                        ppath="$(echo "$target_line" | awk -F'\t' '{print $9}')"
                        if [ -f "$PROJECT_ROOT/src/bookmarks.sh" ]; then
                            # shellcheck source=src/bookmarks.sh
                            source "$PROJECT_ROOT/src/bookmarks.sh"
                            add_bookmark_interactive "$ppath"
                        fi
                    else
                        error "Item number $b_num not found."
                    fi
                fi
                ;;
            S)
                if [ -f "$PROJECT_ROOT/src/inspector.sh" ]; then
                    # shellcheck source=src/inspector.sh
                    source "$PROJECT_ROOT/src/inspector.sh"
                    audit_suspicious_indicators "$LAST_RESULTS_FILE"
                else
                    error "Inspector module not available."
                fi
                ;;
            *)
                # Check if it's an item number to inspect
                if [[ "$action" =~ ^[0-9]+$ ]]; then
                    local target_line
                    target_line="$(awk -F'\t' -v n="$action" '$1 == n {print $0}' "$LAST_RESULTS_FILE")"
                    if [ -n "$target_line" ]; then
                        local ppath
                        ppath="$(echo "$target_line" | awk -F'\t' '{print $9}')"
                        if [ -f "$PROJECT_ROOT/src/inspector.sh" ]; then
                            # shellcheck source=src/inspector.sh
                            source "$PROJECT_ROOT/src/inspector.sh"
                            inspect_metadata "$ppath"
                        else
                            info "Path: $ppath"
                        fi
                    else
                        error "Item number $action not found in results."
                    fi
                else
                    warn "Unrecognized action: $action"
                fi
                ;;
        esac
    done
}
