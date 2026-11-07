#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: filters.sh
# Purpose: Advanced multi-attribute search filtering & find query compiler
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

# ------------------------------------------------------------------------------
# Advanced Search Builder & Interactive Interface
# ------------------------------------------------------------------------------
advanced_search_menu() {
    local filter_kw=""
    local filter_ext=""
    local filter_min_size=""
    local filter_max_size=""
    local filter_days=""
    local filter_type="all" # all, file, folder
    local filter_exact=0
    local filter_target="auto"

    while true; do
        clear_screen
        print_banner
        print_header "ADVANCED SEARCH & FILTER BUILDER"
        printf "Configure one or more search filters to narrow down your investigation:\n\n"

        printf "  %s1.%s Keyword / Name Pattern:  %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ -n "$filter_kw" ] && echo "$filter_kw" || echo "[Any / None]")" "$C_RESET"
        printf "  %s2.%s File Extension(s):       %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ -n "$filter_ext" ] && echo "$filter_ext" || echo "[All Extensions]")" "$C_RESET"
        printf "  %s3.%s Minimum Size:            %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ -n "$filter_min_size" ] && echo "$filter_min_size" || echo "[None]")" "$C_RESET"
        printf "  %s4.%s Maximum Size:            %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ -n "$filter_max_size" ] && echo "$filter_max_size" || echo "[None]")" "$C_RESET"
        printf "  %s5.%s Modified Within:         %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ -n "$filter_days" ] && echo "Last $filter_days days" || echo "[Any Time]")" "$C_RESET"
        printf "  %s6.%s Target Item Type:        %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "${filter_type^^}" "$C_RESET"
        printf "  %s7.%s Exact vs Partial Match:  %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$([ "$filter_exact" = "1" ] && echo "Exact Match" || echo "Partial Match")" "$C_RESET"
        printf "  %s8.%s Target Drive / Root:     %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$filter_target" "$C_RESET"
        print_divider
        printf "  %s[S]%s Execute Search With Current Filters\n" "$C_GREEN" "$C_RESET"
        printf "  %s[R]%s Reset All Filters\n" "$C_YELLOW" "$C_RESET"
        printf "  %s[0]%s Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect option: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "${choice^^}" in
            1)
                printf "Enter keyword or pattern (e.g. report, chrome, *log*): "
                read -r filter_kw
                ;;
            2)
                printf "Enter comma-separated extensions (e.g. pdf, txt, exe, log): "
                read -r filter_ext
                filter_ext="$(echo "$filter_ext" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
                ;;
            3)
                printf "Enter minimum size with unit (e.g. 500c for bytes, 10k, 5M, 1G): "
                read -r filter_min_size
                ;;
            4)
                printf "Enter maximum size with unit (e.g. 50M, 1G): "
                read -r filter_max_size
                ;;
            5)
                printf "Enter number of days (e.g. 1 for last 24h, 7 for last week, 30 for last month): "
                read -r filter_days
                ;;
            6)
                if [ "$filter_type" = "all" ]; then
                    filter_type="file"
                elif [ "$filter_type" = "file" ]; then
                    filter_type="folder"
                else
                    filter_type="all"
                fi
                ;;
            7)
                if [ "$filter_exact" = "1" ]; then
                    filter_exact=0
                else
                    filter_exact=1
                fi
                ;;
            8)
                read -r -a sel_roots <<< "$(select_scan_targets)"
                filter_target="${sel_roots[*]}"
                ;;
            R)
                filter_kw=""
                filter_ext=""
                filter_min_size=""
                filter_max_size=""
                filter_days=""
                filter_type="all"
                filter_exact=0
                filter_target="auto"
                success "Filters reset."
                sleep 1
                ;;
            S)
                execute_advanced_search "$filter_kw" "$filter_ext" "$filter_min_size" "$filter_max_size" "$filter_days" "$filter_type" "$filter_exact" "$filter_target"
                ;;
            0|Q)
                break
                ;;
            *)
                warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Compile & Execute Filtered Search
# ------------------------------------------------------------------------------
execute_advanced_search() {
    local kw="$1"
    local ext="$2"
    local min_sz="$3"
    local max_sz="$4"
    local days="$5"
    local item_type="$6"
    local exact="$7"
    local target="$8"

    # Determine roots
    local roots=()
    if [ -n "$target" ] && [ "$target" != "auto" ]; then
        # shellcheck disable=SC2206
        roots=($target)
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
    print_header "EXECUTING ADVANCED FILTERED INVESTIGATION"
    
    # Build find expressions
    local find_args=()

    # Symlink flag
    local symlink_flag="-P"
    [ "$CFG_FOLLOW_SYMLINKS" = "1" ] && symlink_flag="-L"

    # Type
    case "$item_type" in
        file)   find_args+=("-type" "f") ;;
        folder) find_args+=("-type" "d") ;;
    esac

    # Keyword / Name pattern
    if [ -n "$kw" ]; then
        local pattern
        if [ "$exact" = "1" ]; then
            pattern="$kw"
        else
            pattern="*${kw}*"
        fi
        if [ "$CFG_CASE_SENSITIVE" = "1" ]; then
            find_args+=("-name" "$pattern")
        else
            find_args+=("-iname" "$pattern")
        fi
    fi

    # Extension filter (only applies to files or all)
    if [ -n "$ext" ]; then
        IFS=',' read -ra ext_list <<< "$ext"
        if [ ${#ext_list[@]} -eq 1 ]; then
            find_args+=("-iname" "*.${ext_list[0]}")
        elif [ ${#ext_list[@]} -gt 1 ]; then
            find_args+=("(")
            local first_ext=1
            for e in "${ext_list[@]}"; do
                e="$(echo "$e" | tr -d '[:space:]')"
                [ -z "$e" ] && continue
                if [ "$first_ext" -eq 1 ]; then
                    find_args+=("-iname" "*.$e")
                    first_ext=0
                else
                    find_args+=("-o" "-iname" "*.$e")
                fi
            done
            find_args+=(")")
        fi
    fi

    # Min size
    if [ -n "$min_sz" ]; then
        find_args+=("-size" "+$min_sz")
    fi

    # Max size
    if [ -n "$max_sz" ]; then
        find_args+=("-size" "-$max_sz")
    fi

    # Modification days
    if [ -n "$days" ] && [[ "$days" =~ ^[0-9]+$ ]]; then
        find_args+=("-mtime" "-$days")
    fi

    # Pruning args
    local prune_args
    read -r -a prune_args <<< "$(build_find_prune_args)"

    init_scan_log
    local start_time
    start_time=$(date +%s)

    local temp_raw="$PROJECT_ROOT/data/tmp_adv_raw.txt"
    ensure_dir "$PROJECT_ROOT/data"
    : > "$temp_raw"

    info "Scanning across: ${roots[*]}"
    for r in "${roots[@]}"; do
        [ ! -d "$r" ] && continue
        if [ ${#prune_args[@]} -gt 0 ]; then
            find "$symlink_flag" "$r" "${prune_args[@]}" \
                "${find_args[@]}" \
                -printf '%s|%T@|%y|%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        else
            find "$symlink_flag" "$r" \
                "${find_args[@]}" \
                -printf '%s|%T@|%y|%p\n' 2>> "$SCAN_ERROR_LOG" >> "$temp_raw"
        fi
    done

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    [ "$elapsed" -eq 0 ] && elapsed=1

    # Populate LAST_RESULTS_FILE with rank
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
        local mtime_int="${r_mtime%.*}"
        [ -z "$mtime_int" ] && mtime_int=0

        local ext_col=""
        if [ "$r_type" = "f" ]; then
            ext_col="$(get_file_extension "$bname")"
        else
            ext_col="[DIR]"
        fi

        local win_path
        win_path="$(to_win_path "$r_path")"

        if [ "$count" -le "$CFG_MAX_RESULTS" ]; then
            # Rank 1 if exact match, otherwise rank 3
            local rank=3
            [ "$r_type" = "d" ] && rank=4
            printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$count" "$rank" "$r_type" "$bname" "$ext_col" "$r_size" "$mtime_int" "$win_path" "$r_path" >> "$LAST_RESULTS_FILE"
        fi
    done < "$temp_raw"

    rm -f "$temp_raw"

    local search_summary_kw="Filter:[ext=${ext:-*},size=${min_sz:-0}-${max_sz:-max},kw=${kw:-*}]"
    display_search_results "$search_summary_kw" "$count" "$file_count" "$folder_count" "$elapsed"
}
