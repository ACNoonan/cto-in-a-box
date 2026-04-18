#!/bin/bash
# =============================================================================
# ECS SERVICE LOG VIEWER
# =============================================================================
# Fetches CloudWatch logs for ECS services in the prod cluster.
# Designed for both human and AI agent use — supports structured output,
# flexible time ranges, and pattern filtering.
#
# All services log to the shared /ecs/prod CloudWatch log group with
# stream prefixes matching service names (e.g., user-api/, driver-api/).
#
# Usage: ./ecs-logs.sh [OPTIONS] [service]
#
# Quick examples:
#   ./ecs-logs.sh user-api                        # Last 15min of user-api logs
#   ./ecs-logs.sh user-api --since 1h --errors    # Errors in the last hour
#   ./ecs-logs.sh user-api --filter "booking"     # Search for "booking"
#   ./ecs-logs.sh user-api --follow               # Tail logs in real-time
#   ./ecs-logs.sh user-api --since 6h --json      # JSON output for AI parsing
# =============================================================================

set -e

# Configuration (rendered by cto-bootstrap)
LOG_GROUP="{{ECS_LOG_GROUP}}"
REGION="{{AWS_REGION}}"
CLUSTER="{{ECS_CLUSTER}}"

# Service configuration: "service_name:stream_prefix"
# Stream prefix is what the ECS task definition uses for awslogs-stream-prefix.
# Dev services share the same log group with dev- prefixed streams.
SERVICES_CONFIG=(
{{LOG_SERVICES_CONFIG_LINES}}
)

# Defaults
DEFAULT_SINCE="15m"
DEFAULT_LINES=200
MAX_LINES=2000

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

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${CYAN}ℹ${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_verbose() {
    if $VERBOSE; then
        echo -e "${DIM}   [debug] $1${NC}" >&2
    fi
}

# Get list of service names
get_service_names() {
    for config in "${SERVICES_CONFIG[@]}"; do
        echo "${config%%:*}"
    done
}

# Get stream prefix for a service
get_stream_prefix() {
    local service=$1
    for config in "${SERVICES_CONFIG[@]}"; do
        local svc="${config%%:*}"
        if [[ "$svc" == "$service" ]]; then
            echo "${config#*:}"
            return
        fi
    done
    echo ""
}

# Parse a human-friendly duration into seconds
# Supports: 5m, 15m, 1h, 6h, 24h, 1d, 7d, 30d
parse_duration_to_seconds() {
    local input=$1
    local number="${input%[smhd]}"
    local unit="${input##*[0-9]}"

    # Validate number is actually a number
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        echo ""
        return
    fi

    case "$unit" in
        s) echo $((number)) ;;
        m) echo $((number * 60)) ;;
        h) echo $((number * 3600)) ;;
        d) echo $((number * 86400)) ;;
        *)
            echo ""
            ;;
    esac
}

# Convert duration to milliseconds-since-epoch start time
duration_to_start_ms() {
    local since=$1
    local seconds
    seconds=$(parse_duration_to_seconds "$since")

    if [[ -z "$seconds" ]]; then
        log_error "Invalid duration format: $since"
        log_error "Use format like: 5m, 15m, 1h, 6h, 24h, 7d"
        exit 1
    fi

    local now_ms
    now_ms=$(date +%s)
    echo $(( (now_ms - seconds) * 1000 ))
}

# Format a CloudWatch timestamp (ms since epoch) to human-readable
format_timestamp() {
    local ms=$1
    local seconds=$((ms / 1000))
    # macOS date command
    if date -r 0 &>/dev/null 2>&1; then
        date -r "$seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ms"
    else
        # Linux date command
        date -d "@$seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ms"
    fi
}

# Show header
show_header() {
    echo "" >&2
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║${NC}                 ${BOLD}${WHITE}ECS SERVICE LOG VIEWER${NC}                              ${CYAN}║${NC}" >&2
    echo -e "${CYAN}║${NC}                 Log group: ${YELLOW}${LOG_GROUP}${NC}                            ${CYAN}║${NC}" >&2
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
}

# =============================================================================
# Log Fetching Functions
# =============================================================================

# Fetch logs using filter-log-events (historical query)
fetch_logs() {
    local service=$1
    local since=$2
    local filter=$3
    local max_lines=$4
    local json_mode=$5

    local stream_prefix=""
    if [[ "$service" != "all" ]]; then
        stream_prefix=$(get_stream_prefix "$service")
        if [[ -z "$stream_prefix" ]]; then
            log_error "Unknown service: $service"
            exit 1
        fi
    fi

    local start_ms
    start_ms=$(duration_to_start_ms "$since")

    log_verbose "Fetching logs for $service (prefix: ${stream_prefix:-<all>})"
    log_verbose "Time range: $since ago (start: $start_ms)"
    log_verbose "Filter: ${filter:-<none>}"
    log_verbose "Max lines: $max_lines"

    # Build the AWS CLI command
    # NOTE: No --no-paginate — we need full pagination to catch logs across
    # all ECS task generations. Without it, only the first page (oldest events)
    # is returned, silently dropping newer events from task replacements.
    local cmd=(
        aws logs filter-log-events
        --log-group-name "$LOG_GROUP"
        --start-time "$start_ms"
        --region "$REGION"
    )

    # Scope to a specific service's streams, or search the entire log group (--all)
    if [[ -n "$stream_prefix" ]]; then
        cmd+=(--log-stream-name-prefix "${stream_prefix}/")
    fi

    if [[ -n "$filter" ]]; then
        cmd+=(--filter-pattern "$filter")
    fi

    log_verbose "Command: ${cmd[*]}"

    # Execute and process — full pagination ensures we see logs from all task
    # generations, not just the currently running ECS task.
    local raw_output
    raw_output=$(AWS_PAGER="" "${cmd[@]}" 2>/dev/null)

    if [[ $? -ne 0 || -z "$raw_output" ]]; then
        if [[ "$json_mode" == "true" ]]; then
            echo '{"service":"'"$service"'","since":"'"$since"'","filter":"'"${filter}"'","events":[],"count":0,"truncated":false}'
        else
            log_warning "No logs found for $service in the last $since"
        fi
        return
    fi

    local total_count
    total_count=$(echo "$raw_output" | jq '.events | length')

    if [[ "$json_mode" == "true" ]]; then
        # Structured JSON output for AI agents
        local truncated="false"
        if [[ $total_count -gt $max_lines ]]; then
            truncated="true"
        fi
        echo "$raw_output" | jq --arg service "$service" \
            --arg since "$since" \
            --arg filter "${filter}" \
            --arg truncated "$truncated" \
            --argjson max_lines "$max_lines" '{
            service: $service,
            since: $since,
            filter: ($filter // null),
            count: (.events | length),
            showing: (if (.events | length) > $max_lines then $max_lines else (.events | length) end),
            truncated: ($truncated == "true"),
            events: [.events | sort_by(.timestamp) | .[-$max_lines:][] | {
                timestamp: .timestamp,
                time: (.timestamp / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
                stream: .logStreamName,
                message: (.message | rtrimstr("\n"))
            }]
        }'
    else
        # Human-readable output
        local showing=$total_count
        if [[ $total_count -gt $max_lines ]]; then
            showing=$max_lines
            log_info "Found $total_count events, showing last $max_lines (use --lines to increase)"
        else
            log_info "Found $total_count events"
        fi
        echo "" >&2

        echo "$raw_output" | jq -r --argjson max_lines "$max_lines" '
            .events | sort_by(.timestamp) | .[-$max_lines:][] |
            (.timestamp / 1000 | strftime("%H:%M:%S")) + " " + (.message | rtrimstr("\n"))
        '
    fi
}

# Tail logs in real-time using aws logs tail
tail_logs() {
    local service=$1
    local since=$2
    local filter=$3

    local stream_prefix=""
    if [[ "$service" != "all" ]]; then
        stream_prefix=$(get_stream_prefix "$service")
        if [[ -z "$stream_prefix" ]]; then
            log_error "Unknown service: $service"
            exit 1
        fi
    fi

    log_info "Tailing ${CYAN}$service${NC} logs (since $since)..."
    log_info "Press Ctrl+C to stop"
    echo "" >&2

    # aws logs tail supports --since with relative times
    local cmd=(
        aws logs tail "$LOG_GROUP"
        --since "$since"
        --follow
        --region "$REGION"
        --format short
    )

    if [[ -n "$stream_prefix" ]]; then
        cmd+=(--log-stream-name-prefix "${stream_prefix}/")
    fi

    if [[ -n "$filter" ]]; then
        cmd+=(--filter-pattern "$filter")
    fi

    "${cmd[@]}" 2>/dev/null
}

# Generate a summary of log patterns (error counts, most frequent messages)
show_summary() {
    local service=$1
    local since=$2
    local filter=$3

    local stream_prefix=""
    if [[ "$service" != "all" ]]; then
        stream_prefix=$(get_stream_prefix "$service")
        if [[ -z "$stream_prefix" ]]; then
            log_error "Unknown service: $service"
            exit 1
        fi
    fi

    local start_ms
    start_ms=$(duration_to_start_ms "$since")

    log_info "Analyzing logs for ${CYAN}$service${NC} (last $since)..."
    echo "" >&2

    # Fetch all logs for the period — full pagination for accurate counts
    local cmd=(
        aws logs filter-log-events
        --log-group-name "$LOG_GROUP"
        --start-time "$start_ms"
        --region "$REGION"
    )

    if [[ -n "$stream_prefix" ]]; then
        cmd+=(--log-stream-name-prefix "${stream_prefix}/")
    fi

    if [[ -n "$filter" ]]; then
        cmd+=(--filter-pattern "$filter")
    fi

    local raw_output
    raw_output=$(AWS_PAGER="" "${cmd[@]}" 2>/dev/null)

    if [[ -z "$raw_output" ]]; then
        log_warning "No logs found for $service in the last $since"
        return
    fi

    local total
    total=$(echo "$raw_output" | jq '.events | length')

    # Count by log level
    local errors warnings infos
    errors=$(echo "$raw_output" | jq '[.events[].message | select(test("\\[ERROR\\]"))] | length')
    warnings=$(echo "$raw_output" | jq '[.events[].message | select(test("\\[WARN\\]"))] | length')
    infos=$(echo "$raw_output" | jq '[.events[].message | select(test("\\[INFO\\]"))] | length')

    echo -e "${BOLD}${WHITE}Log Summary: ${CYAN}$service${NC} ${GRAY}(last $since)${NC}"
    echo -e "─────────────────────────────────────────────"
    echo ""
    echo -e "  ${WHITE}Total events:${NC}  $total"
    echo -e "  ${RED}Errors:${NC}        $errors"
    echo -e "  ${YELLOW}Warnings:${NC}      $warnings"
    echo -e "  ${BLUE}Info:${NC}          $infos"
    echo ""

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}${BOLD}Recent Errors:${NC}"
        echo -e "─────────────────────────────────────────────"
        echo "$raw_output" | jq -r --argjson limit 10 '
            [.events[] | select(.message | test("\\[ERROR\\]"))] |
            sort_by(.timestamp) |
            .[-$limit:][] |
            (.timestamp / 1000 | strftime("%H:%M:%S")) + " " + (.message | rtrimstr("\n"))
        '
        echo ""
    fi

    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}Recent Warnings:${NC} ${GRAY}(last 5)${NC}"
        echo -e "─────────────────────────────────────────────"
        echo "$raw_output" | jq -r --argjson limit 5 '
            [.events[] | select(.message | test("\\[WARN\\]"))] |
            sort_by(.timestamp) |
            .[-$limit:][] |
            (.timestamp / 1000 | strftime("%H:%M:%S")) + " " + (.message | rtrimstr("\n"))
        '
        echo ""
    fi
}

# =============================================================================
# Service Selection (matches check-deployment.sh pattern)
# =============================================================================

select_service() {
    local service_arg=$1

    if [[ -n "$service_arg" ]]; then
        echo "$service_arg"
        return
    fi

    # Interactive selection
    echo -e "${WHITE}Available services:${NC}" > /dev/tty
    echo "" > /dev/tty

    local services_list=()
    while IFS= read -r svc; do
        services_list+=("$svc")
    done < <(get_service_names)

    for i in "${!services_list[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${services_list[$i]}" > /dev/tty
    done
    echo "" > /dev/tty

    read -p "Select service: " selection < /dev/tty

    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#services_list[@]} ]]; then
        echo "${services_list[$((selection-1))]}"
    else
        # Try as service name
        echo "$selection"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local follow_mode=false
    local json_mode=false
    local summary_mode=false
    local all_services=false
    local service_arg=""
    local since="$DEFAULT_SINCE"
    local filter=""
    local max_lines=$DEFAULT_LINES
    VERBOSE=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                all_services=true
                shift
                ;;
            --since|-s)
                since="$2"
                shift 2
                ;;
            --filter)
                filter="$2"
                shift 2
                ;;
            --errors|-e)
                filter='"[ERROR]"'
                shift
                ;;
            --warnings|-W)
                filter='?"[ERROR]" ?"[WARN]"'
                shift
                ;;
            --follow|-f)
                follow_mode=true
                shift
                ;;
            --lines|-n)
                max_lines="$2"
                if [[ $max_lines -gt $MAX_LINES ]]; then
                    log_warning "Capping lines at $MAX_LINES (requested $max_lines)"
                    max_lines=$MAX_LINES
                fi
                shift 2
                ;;
            --json|-j)
                json_mode=true
                shift
                ;;
            --summary)
                summary_mode=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Run with --help for usage" >&2
                exit 1
                ;;
            *)
                service_arg=$1
                shift
                ;;
        esac
    done

    # Check dependencies
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required. Install with: brew install awscli"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required. Install with: brew install jq"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Run: aws configure"
        exit 1
    fi

    # Show header (unless JSON mode)
    if [[ "$json_mode" != "true" ]]; then
        show_header
    fi

    # Select service (or --all for entire log group)
    local service
    if $all_services; then
        service="all"
    else
        service=$(select_service "$service_arg")

        if [[ -z "$service" ]]; then
            log_error "No service selected. Exiting."
            exit 1
        fi

        # Validate service
        local valid=false
        for config in "${SERVICES_CONFIG[@]}"; do
            local svc="${config%%:*}"
            if [[ "$svc" == "$service" ]]; then
                valid=true
                break
            fi
        done

        if ! $valid; then
            log_error "Unknown service: $service"
            log_error "Valid services: $(get_service_names | tr '\n' ' ')"
            exit 1
        fi
    fi

    if [[ "$json_mode" != "true" ]]; then
        if [[ "$service" == "all" ]]; then
            log_info "Service: ${CYAN}all services${NC} (entire ${LOG_GROUP} log group)"
        else
            log_info "Service: ${CYAN}$service${NC}"
        fi
        log_info "Time range: ${CYAN}$since${NC}"
        if [[ -n "$filter" ]]; then
            log_info "Filter: ${CYAN}$filter${NC}"
        fi
    fi

    # Execute appropriate mode
    if $follow_mode; then
        tail_logs "$service" "$since" "$filter"
    elif $summary_mode; then
        show_summary "$service" "$since" "$filter"
    else
        fetch_logs "$service" "$since" "$filter" "$max_lines" "$json_mode"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS] [service]"
    echo ""
    echo "Fetch CloudWatch logs for ECS services in the production cluster."
    echo "Logs are fetched from the shared $LOG_GROUP log group."
    echo ""
    echo "Services: $(get_service_names | tr '\n' ' ')"
    echo ""
    echo "Options:"
    echo "  --all, -a              Search ALL services (entire $LOG_GROUP log group)"
    echo "  --since, -s DURATION   How far back to look. Default: $DEFAULT_SINCE"
    echo "                         Examples: 5m, 15m, 1h, 6h, 24h, 7d"
    echo "  --filter PATTERN       CloudWatch filter pattern for text search"
    echo "                         Examples: '\"booking\"', '\"timeout\"', '\"userId=abc123\"'"
    echo "  --errors, -e           Shortcut: filter for [ERROR] level logs"
    echo "  --warnings, -W         Shortcut: filter for [ERROR] and [WARN] logs"
    echo "  --follow, -f           Tail logs in real-time (like tail -f)"
    echo "  --lines, -n N          Max log events to return. Default: $DEFAULT_LINES (max: $MAX_LINES)"
    echo "  --json, -j             Output structured JSON (for AI agent consumption)"
    echo "  --summary              Show log level counts and recent errors/warnings"
    echo "  --verbose, -v          Debug output"
    echo "  --help, -h             Show this help"
    echo ""
    echo "Examples:"
    echo ""
    echo "  # Basic usage — last 15 minutes of user-api logs"
    echo "  $0 user-api"
    echo ""
    echo "  # Errors in the last hour"
    echo "  $0 user-api --since 1h --errors"
    echo ""
    echo "  # Search for a specific term"
    echo "  $0 user-api --since 6h --filter '\"booking\"'"
    echo ""
    echo "  # Tail logs in real-time"
    echo "  $0 user-api --follow"
    echo ""
    echo "  # JSON output for AI agent processing"
    echo "  $0 user-api --since 1h --errors --json"
    echo ""
    echo "  # Summary of log patterns"
    echo "  $0 user-api --since 6h --summary"
    echo ""
    echo "  # Search across ALL services (e.g. find a booking across user-api + messenger)"
    echo "  $0 --all --since 6h --filter '\"booking_abc123\"'"
    echo ""
    echo "  # All errors across all services"
    echo "  $0 --all --since 1h --errors"
    echo ""
    echo "  # Large window with more results"
    echo "  $0 messenger --since 24h --lines 500"
    echo ""
    echo "Filter Pattern Syntax (CloudWatch):"
    echo "  '\"exact phrase\"'         Match exact text (must be in double quotes inside single quotes)"
    echo "  '?\"term1\" ?\"term2\"'      Match term1 OR term2"
    echo "  '\"term1\" \"term2\"'        Match term1 AND term2"
    echo "  '\"term1\" - \"term2\"'      Match term1 but NOT term2"
    echo ""
    echo "Exit codes: 0=success, 1=error"
}

# Run
main "$@"
