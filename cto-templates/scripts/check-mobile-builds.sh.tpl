#!/bin/bash
# =============================================================================
# MOBILE BUILD & TESTFLIGHT TRACKER
# =============================================================================
# Tracks EAS builds AND TestFlight submissions for mobile apps.
# Uses EAS CLI for builds + Expo GraphQL API for submission status.
#
# Requires: eas-cli (logged in), jq, curl
#
# Apps: configured in APPS_CONFIG below — fill in once `eas init` has assigned
# project IDs and App Store Connect has registered the apps.
#
# Build States:
#   ✓ done       Build complete, artifact available
#   ⟳ build      Compiling on EAS servers
#   ⟳ queue      Waiting for a builder
#   ✗ error      Build failed
#   ○ cancel     Build canceled
#
# Submission States:
#   ✓ submitted  Successfully uploaded to App Store Connect
#   ⟳ uploading  Submission in progress
#   ⟳ waiting    Awaiting processing
#   ✗ errored    Submission failed
#   ○ canceled   Submission canceled
#
# Usage:
#   ./check-mobile-builds.sh                        # All apps
#   ./check-mobile-builds.sh driver-app             # Single app
#   ./check-mobile-builds.sh --watch                # Watch active builds/submissions
#   ./check-mobile-builds.sh --submit driver-app    # Submit latest to TestFlight
#   ./check-mobile-builds.sh --platform all         # iOS + Android
#   ./check-mobile-builds.sh --limit 10             # More history
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

POLL_INTERVAL=15
DEFAULT_LIMIT=5
DEFAULT_PLATFORM="ios"
EXPO_GRAPHQL="https://api.expo.dev/graphql"

# App config: "name:directory:slug:bundle_id:expo_project_id:asc_app_id"
#
# TODO: fill one entry per mobile app. You can get:
#   - expo_project_id from `eas project:info` (or app.config.ts → extra.eas.projectId)
#   - asc_app_id from App Store Connect URL (the numeric Apple ID).
#
# Example:
#   "my-app:my-app:my-org-my-app:com.example.my:00000000-0000-0000-0000-000000000000:1234567890"
APPS_CONFIG=(
{{MOBILE_APPS_CONFIG_LINES}}
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

SYM_SUCCESS="✓"
SYM_DEPLOYING="⟳"
SYM_FAILED="✗"
SYM_PENDING="○"

# Expo session (loaded once)
EXPO_SESSION=""

# =============================================================================
# App Config Helpers
# =============================================================================

_get_app_field() {
    local app=$1 field_idx=$2
    for config in "${APPS_CONFIG[@]}"; do
        local name="${config%%:*}"
        if [[ "$name" == "$app" ]]; then
            local rest="$config" i=0
            while [[ $i -lt $field_idx ]]; do
                rest="${rest#*:}"
                i=$((i + 1))
            done
            echo "${rest%%:*}"
            return
        fi
    done
}

get_app_dir()        { _get_app_field "$1" 1; }
get_app_slug()       { _get_app_field "$1" 2; }
get_app_bundle_id()  { _get_app_field "$1" 3; }
get_app_project_id() { _get_app_field "$1" 4; }
get_app_asc_id()     { _get_app_field "$1" 5; }

get_all_app_names() {
    for config in "${APPS_CONFIG[@]}"; do
        echo "${config%%:*}"
    done
}

# =============================================================================
# Utility Functions
# =============================================================================

log_info()    { echo -e "${CYAN}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}${SYM_SUCCESS}${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}${SYM_FAILED}${NC} $1"; }

show_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}${WHITE}MOBILE BUILD & TESTFLIGHT TRACKER${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              EAS Builds → TestFlight → App Store                   ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

format_time_ago() {
    local created_at="$1"
    local now
    now=$(date +%s)

    local created_epoch
    if [[ "$(uname)" == "Darwin" ]]; then
        created_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" +%s 2>/dev/null || echo 0)
    else
        created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo 0)
    fi

    [[ "$created_epoch" -eq 0 ]] && echo "$created_at" && return

    local diff=$(( now - created_epoch ))

    if [[ $diff -lt 60 ]]; then echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then echo "$(( diff / 60 ))m ago"
    elif [[ $diff -lt 86400 ]]; then echo "$(( diff / 3600 ))h ago"
    else echo "$(( diff / 86400 ))d ago"
    fi
}

# =============================================================================
# Expo GraphQL API
# =============================================================================

load_expo_session() {
    if [[ -n "$EXPO_SESSION" ]]; then return 0; fi

    local state_file="$HOME/.expo/state.json"
    if [[ ! -f "$state_file" ]]; then
        log_warning "Expo not logged in (~/.expo/state.json not found). Submission tracking unavailable."
        return 1
    fi

    EXPO_SESSION=$(jq -r '.auth.sessionSecret // empty' "$state_file" 2>/dev/null)
    if [[ -z "$EXPO_SESSION" ]]; then
        log_warning "No Expo session found. Run 'eas login' for submission tracking."
        return 1
    fi
    return 0
}

expo_graphql() {
    local query="$1"
    if [[ -z "$EXPO_SESSION" ]]; then return 1; fi

    curl -s "$EXPO_GRAPHQL" \
        -H "Content-Type: application/json" \
        -H "expo-session: $EXPO_SESSION" \
        -d "{\"query\": \"$query\"}" 2>/dev/null
}

# =============================================================================
# EAS Build Functions
# =============================================================================

get_builds() {
    local app=$1 platform=$2 limit=$3
    local app_dir
    app_dir=$(get_app_dir "$app")

    cd "$REPO_ROOT/$app_dir" && eas build:list \
        --platform "$platform" \
        --limit "$limit" \
        --non-interactive \
        --json \
        2>/dev/null \
        < /dev/null
}

has_in_progress_builds() {
    local app=$1
    local app_dir
    app_dir=$(get_app_dir "$app")

    local result
    result=$(cd "$REPO_ROOT/$app_dir" && eas build:list \
        --platform all \
        --status "in-progress" \
        --limit 1 \
        --non-interactive \
        --json \
        2>/dev/null \
        < /dev/null)

    local count
    count=$(echo "$result" | jq 'length' 2>/dev/null || echo "0")
    [[ "$count" -gt 0 ]]
}

# =============================================================================
# Submission Functions (Expo GraphQL)
# =============================================================================

get_submissions() {
    local app=$1 platform=$2 limit=$3
    local project_id
    project_id=$(get_app_project_id "$app")

    if [[ -z "$project_id" ]]; then return 1; fi

    local platform_filter=""
    case "$platform" in
        ios) platform_filter="IOS" ;;
        android) platform_filter="ANDROID" ;;
        *) platform_filter="IOS" ;;
    esac

    local query="{ app { byId(appId: \\\"${project_id}\\\") { submissions(filter: { platform: ${platform_filter} }, offset: 0, limit: ${limit}) { id status platform createdAt updatedAt completedAt submittedBuild { id appVersion appBuildVersion } error { message errorCode } } } } }"

    local result
    result=$(expo_graphql "$query")
    if [[ -z "$result" ]]; then return 1; fi

    echo "$result" | jq '.data.app.byId.submissions // []' 2>/dev/null
}

has_in_progress_submissions() {
    local app=$1
    local subs
    subs=$(get_submissions "$app" "ios" 3)
    if [[ -z "$subs" || "$subs" == "null" || "$subs" == "[]" ]]; then return 1; fi

    local active
    active=$(echo "$subs" | jq '[.[] | select(.status == "IN_PROGRESS" or .status == "AWAITING_SUBMISSION_TO_APP_STORE" or .status == "NEW")] | length' 2>/dev/null || echo "0")
    [[ "$active" -gt 0 ]]
}

# =============================================================================
# Display Functions
# =============================================================================

show_app_section() {
    local app=$1 platform=$2 limit=$3
    local bundle_id asc_id
    bundle_id=$(get_app_bundle_id "$app")
    asc_id=$(get_app_asc_id "$app")

    echo -e "${WHITE}${BOLD}${app}${NC} ${GRAY}(${bundle_id})${NC}"

    if [[ -n "$asc_id" ]]; then
        echo -e "  ${DIM}TestFlight: https://appstoreconnect.apple.com/apps/${asc_id}/testflight/ios${NC}"
    fi
    echo ""

    # ── Builds ──
    echo -e "  ${WHITE}${BOLD}EAS Builds${NC}"
    echo ""

    local builds_json
    builds_json=$(get_builds "$app" "$platform" "$limit")

    if [[ -z "$builds_json" || "$builds_json" == "[]" || "$builds_json" == "null" ]]; then
        echo -e "  ${GRAY}No builds found${NC}"
    else
        local count
        count=$(echo "$builds_json" | jq 'length' 2>/dev/null || echo "0")

        echo -e "  ${DIM}STATUS     PLAT     VERSION       PROFILE      AGE        COMMIT${NC}"
        echo -e "  ${DIM}─────────  ───────  ────────────  ───────────  ─────────  ──────────────────────${NC}"

        for i in $(seq 0 $((count - 1))); do
            local build
            build=$(echo "$builds_json" | jq ".[$i]")

            local status platform_val version build_num profile created_at commit_msg build_id
            status=$(echo "$build" | jq -r '.status')
            platform_val=$(echo "$build" | jq -r '.platform')
            version=$(echo "$build" | jq -r '.appVersion // "?"')
            build_num=$(echo "$build" | jq -r '.appBuildVersion // "?"')
            profile=$(echo "$build" | jq -r '.buildProfile // "?"')
            created_at=$(echo "$build" | jq -r '.createdAt // ""')
            commit_msg=$(echo "$build" | jq -r '.gitCommitMessage // "" | split("\n")[0] | if length > 40 then .[0:40] + "…" else . end')
            build_id=$(echo "$build" | jq -r '.id')

            local status_fmt age_fmt plat_fmt version_fmt

            case "$status" in
                FINISHED)    status_fmt="${GREEN}${SYM_SUCCESS} done  ${NC}" ;;
                IN_PROGRESS) status_fmt="${YELLOW}${SYM_DEPLOYING} build ${NC}" ;;
                IN_QUEUE)    status_fmt="${BLUE}${SYM_DEPLOYING} queue ${NC}" ;;
                NEW)         status_fmt="${BLUE}${SYM_PENDING} new   ${NC}" ;;
                ERRORED)     status_fmt="${RED}${SYM_FAILED} error ${NC}" ;;
                CANCELED)    status_fmt="${GRAY}${SYM_PENDING} cancel${NC}" ;;
                *)           status_fmt="${GRAY}? ${status:0:4}  ${NC}" ;;
            esac

            age_fmt=$(format_time_ago "$created_at")

            case "$platform_val" in
                IOS)     plat_fmt="${WHITE}iOS${NC}    " ;;
                ANDROID) plat_fmt="${GREEN}Android${NC}" ;;
                *)       plat_fmt="$platform_val" ;;
            esac

            version_fmt="${version} (${build_num})"

            printf "  %b  %b  %-9s %-12s %-10s ${GRAY}%s${NC}\n" \
                "$status_fmt" "$plat_fmt" "$version_fmt" "$profile" "$age_fmt" "$commit_msg"

            if [[ "$status" == "IN_PROGRESS" || "$status" == "IN_QUEUE" || "$status" == "ERRORED" ]]; then
                echo -e "  ${DIM}  ↳ https://expo.dev/accounts/{{EXPO_ACCOUNT_SLUG}}/projects/$(get_app_slug "$app")/builds/${build_id}${NC}"
            fi
        done
    fi

    echo ""

    # ── Submissions ──
    if [[ -n "$EXPO_SESSION" ]]; then
        echo -e "  ${WHITE}${BOLD}TestFlight Submissions${NC}"
        echo ""

        local subs_json
        subs_json=$(get_submissions "$app" "$platform" "$limit")

        if [[ -z "$subs_json" || "$subs_json" == "[]" || "$subs_json" == "null" ]]; then
            echo -e "  ${GRAY}No submissions found${NC}"
        else
            local sub_count
            sub_count=$(echo "$subs_json" | jq 'length' 2>/dev/null || echo "0")

            echo -e "  ${DIM}STATUS        VERSION       AGE        SUBMISSION ID${NC}"
            echo -e "  ${DIM}────────────  ────────────  ─────────  ────────────────────────────────────${NC}"

            for i in $(seq 0 $((sub_count - 1))); do
                local sub
                sub=$(echo "$subs_json" | jq ".[$i]")

                local sub_status sub_created sub_id sub_version sub_build_num sub_error
                sub_status=$(echo "$sub" | jq -r '.status')
                sub_created=$(echo "$sub" | jq -r '.createdAt // ""')
                sub_id=$(echo "$sub" | jq -r '.id')
                sub_version=$(echo "$sub" | jq -r '.submittedBuild.appVersion // "?"')
                sub_build_num=$(echo "$sub" | jq -r '.submittedBuild.appBuildVersion // "?"')
                sub_error=$(echo "$sub" | jq -r '.error.message // empty')

                local sub_status_fmt sub_age_fmt sub_ver_fmt

                case "$sub_status" in
                    FINISHED)
                        sub_status_fmt="${GREEN}${SYM_SUCCESS} submitted ${NC}" ;;
                    IN_PROGRESS|AWAITING_SUBMISSION_TO_APP_STORE)
                        sub_status_fmt="${YELLOW}${SYM_DEPLOYING} uploading ${NC}" ;;
                    NEW)
                        sub_status_fmt="${BLUE}${SYM_DEPLOYING} waiting   ${NC}" ;;
                    ERRORED)
                        sub_status_fmt="${RED}${SYM_FAILED} errored   ${NC}" ;;
                    CANCELED)
                        sub_status_fmt="${GRAY}${SYM_PENDING} canceled  ${NC}" ;;
                    *)
                        sub_status_fmt="${GRAY}? ${sub_status:0:8}  ${NC}" ;;
                esac

                sub_age_fmt=$(format_time_ago "$sub_created")
                sub_ver_fmt="${sub_version} (${sub_build_num})"

                printf "  %b  %-13s %-10s ${GRAY}%s${NC}\n" \
                    "$sub_status_fmt" "$sub_ver_fmt" "$sub_age_fmt" "${sub_id:0:36}"

                if [[ "$sub_status" == "IN_PROGRESS" || "$sub_status" == "AWAITING_SUBMISSION_TO_APP_STORE" ]]; then
                    echo -e "  ${DIM}  ↳ https://expo.dev/accounts/{{EXPO_ACCOUNT_SLUG}}/projects/$(get_app_slug "$app")/submissions/${sub_id}${NC}"
                fi

                if [[ -n "$sub_error" ]]; then
                    echo -e "  ${RED}  ↳ ${sub_error}${NC}"
                fi
            done
        fi

        echo ""
    fi

    echo ""
}

# =============================================================================
# Watch Mode
# =============================================================================

watch_active() {
    local apps=("$@")
    local start_time
    start_time=$(date +%s)
    local spin_idx=0
    local SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    echo -e "${WHITE}Watching builds & submissions — polling every ${POLL_INTERVAL}s...${NC}"
    echo -e "${DIM}Press Ctrl+C to exit${NC}"
    echo ""

    # Discover what to track: builds (via EAS CLI) and submissions (via GraphQL)
    declare -a track_ids=()
    declare -a track_apps=()
    declare -a track_types=()   # "build" or "submission"

    for app in "${apps[@]}"; do
        local app_dir
        app_dir=$(get_app_dir "$app")

        # Active EAS builds
        for build_status in "in-progress" "in-queue" "new"; do
            local builds
            builds=$(cd "$REPO_ROOT/$app_dir" && eas build:list \
                --platform all \
                --status "$build_status" \
                --limit 5 \
                --non-interactive \
                --json \
                2>/dev/null \
                < /dev/null)

            if [[ -n "$builds" && "$builds" != "[]" && "$builds" != "null" ]]; then
                local ids
                ids=$(echo "$builds" | jq -r '.[].id' 2>/dev/null)
                while IFS= read -r bid; do
                    if [[ -n "$bid" ]]; then
                        track_ids+=("$bid")
                        track_apps+=("$app")
                        track_types+=("build")
                    fi
                done <<< "$ids"
            fi
        done

        # Active submissions (via GraphQL)
        if [[ -n "$EXPO_SESSION" ]]; then
            local subs
            subs=$(get_submissions "$app" "ios" 5)
            if [[ -n "$subs" && "$subs" != "null" && "$subs" != "[]" ]]; then
                local active_subs
                active_subs=$(echo "$subs" | jq -r '[.[] | select(.status == "IN_PROGRESS" or .status == "AWAITING_SUBMISSION_TO_APP_STORE" or .status == "NEW")] | .[].id' 2>/dev/null)
                while IFS= read -r sid; do
                    if [[ -n "$sid" ]]; then
                        track_ids+=("$sid")
                        track_apps+=("$app")
                        track_types+=("submission")
                    fi
                done <<< "$active_subs"
            fi
        fi
    done

    if [[ ${#track_ids[@]} -eq 0 ]]; then
        log_info "No active builds or submissions. Showing latest status."
        echo ""
        for app in "${apps[@]}"; do
            show_app_section "$app" "ios" 3
        done
        return 0
    fi

    local build_count=0 sub_count=0
    for t in "${track_types[@]}"; do
        [[ "$t" == "build" ]] && build_count=$((build_count + 1))
        [[ "$t" == "submission" ]] && sub_count=$((sub_count + 1))
    done
    log_info "Tracking ${build_count} build(s), ${sub_count} submission(s)..."
    echo ""

    for _ in "${track_ids[@]}"; do echo ""; done

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$(( current_time - start_time ))
        local all_done=true

        printf "\033[%dA" "${#track_ids[@]}"

        for i in "${!track_ids[@]}"; do
            local tid="${track_ids[$i]}"
            local app="${track_apps[$i]}"
            local ttype="${track_types[$i]}"
            local spin="${SPINNER[$spin_idx]}"

            if [[ "$ttype" == "build" ]]; then
                local app_dir
                app_dir=$(get_app_dir "$app")
                local build_json
                build_json=$(cd "$REPO_ROOT/$app_dir" && eas build:list \
                    --platform all \
                    --limit 10 \
                    --non-interactive \
                    --json \
                    2>/dev/null \
                    < /dev/null | jq ".[] | select(.id == \"$tid\")" 2>/dev/null)

                local status version build_num platform_val
                status=$(echo "$build_json" | jq -r '.status // "UNKNOWN"')
                version=$(echo "$build_json" | jq -r '.appVersion // "?"')
                build_num=$(echo "$build_json" | jq -r '.appBuildVersion // "?"')
                platform_val=$(echo "$build_json" | jq -r '.platform // "?"')

                local plat_label=""
                case "$platform_val" in IOS) plat_label="iOS" ;; ANDROID) plat_label="Android" ;; *) plat_label="$platform_val" ;; esac
                local ver_str="${version} (${build_num})"

                case "$status" in
                    FINISHED)
                        printf "  ${GREEN}${SYM_SUCCESS}${NC} %-12s ${WHITE}build${NC}   ${GREEN}FINISHED${NC}  %-7s %-12s %ds                    \n" \
                            "$app" "$plat_label" "$ver_str" "$elapsed" ;;
                    IN_PROGRESS)
                        all_done=false
                        printf "  ${YELLOW}${spin}${NC} %-12s ${WHITE}build${NC}   ${YELLOW}BUILDING${NC}  %-7s %-12s %ds                    \n" \
                            "$app" "$plat_label" "$ver_str" "$elapsed" ;;
                    IN_QUEUE|NEW)
                        all_done=false
                        printf "  ${BLUE}${spin}${NC} %-12s ${WHITE}build${NC}   ${BLUE}QUEUED${NC}    %-7s %-12s %ds                    \n" \
                            "$app" "$plat_label" "$ver_str" "$elapsed" ;;
                    ERRORED)
                        printf "  ${RED}${SYM_FAILED}${NC} %-12s ${WHITE}build${NC}   ${RED}ERRORED${NC}   %-7s %-12s                           \n" \
                            "$app" "$plat_label" "$ver_str" ;;
                    CANCELED)
                        printf "  ${GRAY}${SYM_PENDING}${NC} %-12s ${WHITE}build${NC}   ${GRAY}CANCELED${NC}  %-7s %-12s                           \n" \
                            "$app" "$plat_label" "$ver_str" ;;
                    *)
                        all_done=false
                        printf "  ${GRAY}?${NC} %-12s ${WHITE}build${NC}   %-10s %-7s %-12s                           \n" \
                            "$app" "$status" "$plat_label" "$ver_str" ;;
                esac

            elif [[ "$ttype" == "submission" ]]; then
                local project_id
                project_id=$(get_app_project_id "$app")
                local sub_json
                sub_json=$(expo_graphql "{ app { byId(appId: \\\"${project_id}\\\") { submissions(filter: { platform: IOS }, offset: 0, limit: 5) { id status submittedBuild { appVersion appBuildVersion } } } } }" | jq ".data.app.byId.submissions[] | select(.id == \"$tid\")" 2>/dev/null)

                local sub_status sub_version sub_build_num
                sub_status=$(echo "$sub_json" | jq -r '.status // "UNKNOWN"')
                sub_version=$(echo "$sub_json" | jq -r '.submittedBuild.appVersion // "?"')
                sub_build_num=$(echo "$sub_json" | jq -r '.submittedBuild.appBuildVersion // "?"')
                local ver_str="${sub_version} (${sub_build_num})"

                case "$sub_status" in
                    FINISHED)
                        printf "  ${GREEN}${SYM_SUCCESS}${NC} %-12s ${MAGENTA}submit${NC}  ${GREEN}SUBMITTED${NC} %-7s %-12s %ds                    \n" \
                            "$app" "" "$ver_str" "$elapsed" ;;
                    IN_PROGRESS|AWAITING_SUBMISSION_TO_APP_STORE)
                        all_done=false
                        printf "  ${YELLOW}${spin}${NC} %-12s ${MAGENTA}submit${NC}  ${YELLOW}UPLOADING${NC} %-7s %-12s %ds                    \n" \
                            "$app" "" "$ver_str" "$elapsed" ;;
                    NEW)
                        all_done=false
                        printf "  ${BLUE}${spin}${NC} %-12s ${MAGENTA}submit${NC}  ${BLUE}WAITING${NC}   %-7s %-12s %ds                    \n" \
                            "$app" "" "$ver_str" "$elapsed" ;;
                    ERRORED)
                        printf "  ${RED}${SYM_FAILED}${NC} %-12s ${MAGENTA}submit${NC}  ${RED}ERRORED${NC}   %-7s %-12s                           \n" \
                            "$app" "" "$ver_str" ;;
                    CANCELED)
                        printf "  ${GRAY}${SYM_PENDING}${NC} %-12s ${MAGENTA}submit${NC}  ${GRAY}CANCELED${NC}  %-7s %-12s                           \n" \
                            "$app" "" "$ver_str" ;;
                    *)
                        all_done=false
                        printf "  ${GRAY}?${NC} %-12s ${MAGENTA}submit${NC}  %-10s %-7s %-12s                           \n" \
                            "$app" "$sub_status" "" "$ver_str" ;;
                esac
            fi
        done

        spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))

        if $all_done; then
            echo ""
            echo -e "${GREEN}${BOLD}All builds & submissions complete!${NC}"
            echo ""

            if command -v afplay &> /dev/null; then
                afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
            fi

            for app in "${apps[@]}"; do
                show_app_section "$app" "ios" 3
            done
            break
        fi

        sleep "$POLL_INTERVAL"
    done
}

# =============================================================================
# Submit to TestFlight
# =============================================================================

submit_build() {
    local app=$1 build_id=$2
    local app_dir
    app_dir=$(get_app_dir "$app")

    if [[ -z "$build_id" ]]; then
        echo -e "${WHITE}Submitting latest ${app} build to TestFlight...${NC}"
        echo ""
        cd "$REPO_ROOT/$app_dir" && eas submit \
            --platform ios \
            --latest \
            --non-interactive \
            --verbose
    else
        echo -e "${WHITE}Submitting ${app} build ${build_id} to TestFlight...${NC}"
        echo ""
        cd "$REPO_ROOT/$app_dir" && eas submit \
            --platform ios \
            --id "$build_id" \
            --non-interactive \
            --verbose
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local watch_mode=false
    local submit_mode=false
    local submit_app=""
    local submit_build_id=""
    local selected_apps=()
    local platform="$DEFAULT_PLATFORM"
    local limit="$DEFAULT_LIMIT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --watch|-w)
                watch_mode=true
                shift
                ;;
            --platform|-p)
                platform="$2"
                shift 2
                ;;
            --limit|-l)
                limit="$2"
                shift 2
                ;;
            --submit|-s)
                submit_mode=true
                if [[ -n "$2" && "$2" != --* ]]; then
                    submit_app="$2"
                    shift
                fi
                shift
                ;;
            --build-id)
                submit_build_id="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [app1,app2,...]"
                echo ""
                echo "Track EAS builds and TestFlight submissions."
                echo ""
                echo "Options:"
                echo "  --platform, -p PLAT   Platform: ios, android, all (default: ios)"
                echo "  --limit, -l N         Number of items to show (default: 5)"
                echo "  --watch, -w           Watch mode: poll builds & submissions"
                echo "  --submit, -s [APP]    Submit latest build to TestFlight"
                echo "  --build-id ID         Specific build ID to submit"
                echo "  --help, -h            Show this help"
                echo ""
                echo "Apps: $(get_all_app_names | tr '\n' ' ')"
                echo ""
                echo "Examples:"
                echo "  $0                                       # Status for all apps"
                echo "  $0 driver-app                            # Single app"
                echo "  $0 --watch                                # Watch active builds & submissions"
                echo "  $0 --watch driver-app                     # Watch single app"
                echo "  $0 --submit user-app                      # Submit latest to TestFlight"
                echo "  $0 --submit driver-app --build-id UUID    # Submit specific build"
                echo "  $0 --platform all --limit 10              # All platforms, more history"
                echo ""
                echo "Build States:       Submission States:"
                echo "  ${SYM_SUCCESS} done              ${SYM_SUCCESS} submitted   Uploaded to ASC"
                echo "  ${SYM_DEPLOYING} build             ${SYM_DEPLOYING} uploading   Upload in progress"
                echo "  ${SYM_DEPLOYING} queue             ${SYM_DEPLOYING} waiting     Queued"
                echo "  ${SYM_FAILED} error             ${SYM_FAILED} errored     Submission failed"
                echo "  ${SYM_PENDING} cancel            ${SYM_PENDING} canceled    Canceled"
                echo ""
                exit 0
                ;;
            *)
                IFS=',' read -ra raw_apps <<< "$1"
                for raw in "${raw_apps[@]}"; do
                    raw=$(echo "$raw" | tr -d ' ')
                    local found=false
                    for config in "${APPS_CONFIG[@]}"; do
                        local name="${config%%:*}"
                        if [[ "$name" == "$raw" ]]; then
                            selected_apps+=("$raw")
                            found=true
                            break
                        fi
                    done
                    if ! $found; then
                        log_error "Unknown app: $raw"
                        log_info "Available: $(get_all_app_names | tr '\n' ' ')"
                        exit 1
                    fi
                done
                shift
                ;;
        esac
    done

    # Dependencies
    if ! command -v jq &> /dev/null; then
        log_error "jq is required. Install with: brew install jq"
        exit 1
    fi

    if ! command -v eas &> /dev/null; then
        log_error "eas-cli is required. Install with: npm install -g eas-cli"
        exit 1
    fi

    # Load Expo session for submission tracking (non-fatal if missing)
    load_expo_session || true

    # Default to all apps
    if [[ ${#selected_apps[@]} -eq 0 ]]; then
        while IFS= read -r name; do
            selected_apps+=("$name")
        done < <(get_all_app_names)
    fi

    # Submit mode
    if $submit_mode; then
        local target_app="${submit_app:-${selected_apps[0]}}"
        submit_build "$target_app" "$submit_build_id"
        return $?
    fi

    show_header

    # Auto-switch to watch if anything is active
    if ! $watch_mode; then
        local any_active=false
        for app in "${selected_apps[@]}"; do
            local app_dir
            app_dir=$(get_app_dir "$app")
            if cd "$REPO_ROOT/$app_dir" && has_in_progress_builds "$app"; then
                any_active=true
                break
            fi
            if [[ -n "$EXPO_SESSION" ]] && has_in_progress_submissions "$app"; then
                any_active=true
                break
            fi
        done

        if $any_active; then
            echo -e "${YELLOW}Active build(s) or submission(s) detected — switching to watch mode${NC}"
            echo ""
            watch_mode=true
        fi
    fi

    if $watch_mode; then
        watch_active "${selected_apps[@]}"
    else
        for app in "${selected_apps[@]}"; do
            show_app_section "$app" "$platform" "$limit"
        done
    fi
}

main "$@"
