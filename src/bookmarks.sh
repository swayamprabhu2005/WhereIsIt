#!/usr/bin/env bash
# ==============================================================================
# Where Is It - Digital File System Investigator
# Module: bookmarks.sh
# Purpose: Investigation bookmarks, tagging notes, verification & persistence
# ==============================================================================

if [ -z "$PROJECT_ROOT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=src/utils.sh
    source "$SCRIPT_DIR/utils.sh"
    # shellcheck source=src/settings.sh
    source "$SCRIPT_DIR/settings.sh"
fi

BOOKMARKS_FILE="$PROJECT_ROOT/data/bookmarks.tsv"

# ------------------------------------------------------------------------------
# Add Bookmark
# ------------------------------------------------------------------------------
add_bookmark_interactive() {
    local target_path="$1"
    
    if [ -z "$target_path" ]; then
        printf "Enter path to bookmark: "
        read -r target_path
    fi

    local ppath
    ppath="$(to_posix_path "$target_path")"
    if [ ! -e "$ppath" ]; then
        error "Target does not exist on disk: $target_path"
        press_enter_to_continue
        return 1
    fi

    printf "Enter an investigator note or forensic tag for this bookmark: "
    read -r note
    [ -z "$note" ] && note="Bookmarked item"

    ensure_dir "$PROJECT_ROOT/data"
    local next_id=1
    if [ -f "$BOOKMARKS_FILE" ]; then
        local last_id
        last_id="$(tail -n 1 "$BOOKMARKS_FILE" 2>/dev/null | awk -F'\t' '{print $1}')"
        if [[ "$last_id" =~ ^[0-9]+$ ]]; then
            next_id=$((last_id + 1))
        fi
    fi

    local btype="FILE"
    [ -d "$ppath" ] && btype="DIR "
    local win_path
    win_path="$(to_win_path "$ppath")"
    local ts
    ts="$(get_display_timestamp)"

    # Format: ID \t TIMESTAMP \t TYPE \t NOTE \t WIN_PATH \t POSIX_PATH
    printf "%d\t%s\t%s\t%s\t%s\t%s\n" \
        "$next_id" "$ts" "$btype" "$note" "$win_path" "$ppath" >> "$BOOKMARKS_FILE"

    success "Item bookmarked successfully as Bookmark #$next_id."
    press_enter_to_continue
}

# ------------------------------------------------------------------------------
# View & Manage Bookmarks Menu
# ------------------------------------------------------------------------------
bookmarks_menu() {
    while true; do
        clear_screen
        print_banner
        print_header "INVESTIGATION BOOKMARKS"

        if [ ! -f "$BOOKMARKS_FILE" ] || [ ! -s "$BOOKMARKS_FILE" ]; then
            info "No bookmarks saved yet. You can bookmark any item during search or inspection."
            print_divider
            press_enter_to_continue
            break
        fi

        printf "%s%-4s %-6s %-18s %-22s %-8s %s%s\n" \
            "$C_BOLD$C_BLUE" "ID" "Type" "Date Added" "Note" "Status" "Windows Path" "$C_RESET"
        print_divider

        while IFS=$'\t' read -r bid bts btype bnote win_path ppath || [ -n "$bid" ]; do
            [ -z "$bid" ] && continue

            # Check if path is still present on disk
            local status_badge="$C_GREEN[EXISTS]$C_RESET"
            if [ ! -e "$ppath" ]; then
                status_badge="$C_RED[MISSING]$C_RESET"
            fi

            printf "%s%-4s%s %-6s %-18s %s%-22s%s %-8s %s%s\n" \
                "$C_GRAY" "$bid" "$C_RESET" \
                "$btype" "$bts" \
                "$C_YELLOW" "$bnote" "$C_RESET" \
                "$status_badge" \
                "$C_WHITE" "$win_path" "$C_RESET"
        done < "$BOOKMARKS_FILE"
        print_divider

        printf "  %s[ID]%s Inspect Bookmarked File\n" "$C_CYAN" "$C_RESET"
        printf "  %s[D]%s  Delete Bookmark by ID\n" "$C_CYAN" "$C_RESET"
        printf "  %s[A]%s  Add New Bookmark Path\n" "$C_CYAN" "$C_RESET"
        printf "  %s[0]%s  Return to Main Menu\n" "$C_CYAN" "$C_RESET"
        print_divider

        printf "%sSelect option: %s" "$C_WHITE" "$C_RESET"
        read -r choice
        case "${choice^^}" in
            0|M|"")
                break
                ;;
            A)
                add_bookmark_interactive
                ;;
            D)
                printf "Enter Bookmark ID to remove: "
                read -r del_id
                if [[ "$del_id" =~ ^[0-9]+$ ]]; then
                    local temp_bm="$PROJECT_ROOT/data/tmp_bm.tsv"
                    awk -F'\t' -v id="$del_id" '$1 != id' "$BOOKMARKS_FILE" > "$temp_bm"
                    mv -f "$temp_bm" "$BOOKMARKS_FILE"
                    success "Bookmark #$del_id removed."
                    sleep 1
                fi
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    local entry
                    entry="$(awk -F'\t' -v id="$choice" '$1 == id {print $0}' "$BOOKMARKS_FILE")"
                    if [ -n "$entry" ]; then
                        local inspect_path
                        inspect_path="$(echo "$entry" | awk -F'\t' '{print $6}')"
                        if [ -f "$PROJECT_ROOT/src/inspector.sh" ]; then
                            # shellcheck source=src/inspector.sh
                            source "$PROJECT_ROOT/src/inspector.sh"
                            inspect_metadata "$inspect_path"
                        fi
                    else
                        error "Bookmark ID #$choice not found."
                        sleep 1
                    fi
                fi
                ;;
        esac
    done
}
