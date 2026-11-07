#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: history.sh
# Purpose: Search history tracking, re-execution, result export & management
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
fi

HISTORY_FILE="$PROJECT_ROOT/data/history.tsv"

# ------------------------------------------------------------------------------
# Record Search
# ------------------------------------------------------------------------------
record_search_history() {
    local keyword="$1"
    local targets="$2"
    local mode="$3"
    local count="$4"

    ensure_dir "$PROJECT_ROOT/data"
    
    local next_id=1
    if [ -f "$HISTORY_FILE" ]; then
        local last_id
        last_id="$(tail -n 1 "$HISTORY_FILE" 2>/dev/null | awk -F'\t' '{print $1}')"
        if [[ "$last_id" =~ ^[0-9]+$ ]]; then
            next_id=$((last_id + 1))
        fi
    fi

    local timestamp
    timestamp="$(get_display_timestamp)"

    # Format: ID \t TIMESTAMP \t KEYWORD \t TARGETS \t MODE \t COUNT
    printf "%d\t%s\t%s\t%s\t%s\t%d\n" \
        "$next_id" "$timestamp" "$keyword" "$targets" "$mode" "$count" >> "$HISTORY_FILE"
}

# ------------------------------------------------------------------------------
# View & Manage History Menu
# ------------------------------------------------------------------------------
history_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "SEARCH & INVESTIGATION HISTORY"
        
        if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
            info "Investigation history log is empty."
            print_divider
            press_enter_to_continue
            break
        fi

        printf "%s%-5s %-20s %-20s %-10s %-8s %s%s\n" \
            "$C_BOLD$C_BLUE" "ID" "Date / Time" "Keyword" "Mode" "Results" "Targets" "$C_RESET"
        print_divider

        # Display last 25 searches
        tail -n 25 "$HISTORY_FILE" | while IFS=$'\t' read -r hid htime hkw htargets hmode hcount || [ -n "$hid" ]; do
            [ -z "$hid" ] && continue
            printf "%s%-5s%s %-20s %s%-20s%s %-10s %s%-8d%s %s%s\n" \
                "$C_GRAY" "$hid" "$C_RESET" \
                "$htime" \
                "$C_YELLOW" "$hkw" "$C_RESET" \
                "$hmode" \
                "$C_GREEN" "$hcount" "$C_RESET" \
                "$C_WHITE" "$htargets" "$C_RESET"
        done
        print_divider

        printf "  %s[ID]%s Repeat Investigation by ID\n" "$C_CYAN" "$C_RESET"
        printf "  %s[C]%s  Clear Investigation History\n" "$C_CYAN" "$C_RESET"
        printf "  %s[0]%s  Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect option: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "${choice^^}" in
            0|M|"")
                break
                ;;
            C)
                if prompt_confirm "Clear all search history logs?" "N"; then
                    : > "$HISTORY_FILE"
                    success "Investigation history cleared."
                    sleep 1
                fi
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    local entry
                    entry="$(awk -F'\t' -v id="$choice" '$1 == id {print $0}' "$HISTORY_FILE")"
                    if [ -n "$entry" ]; then
                        local ekw etargets emode
                        ekw="$(echo "$entry" | awk -F'\t' '{print $3}')"
                        etargets="$(echo "$entry" | awk -F'\t' '{print $4}')"
                        emode="$(echo "$entry" | awk -F'\t' '{print $5}')"
                        
                        info "Re-executing search: Keyword='$ekw', Targets='$etargets', Mode='$emode'"
                        if [ -f "$PROJECT_ROOT/src/search.sh" ]; then
                            # shellcheck source=src/search.sh
                            source "$PROJECT_ROOT/src/search.sh"
                            run_search "$ekw" "$emode" 0 "$etargets" 1
                        fi
                    else
                        error "History ID #$choice not found."
                        sleep 1
                    fi
                fi
                ;;
        esac
    done
}
