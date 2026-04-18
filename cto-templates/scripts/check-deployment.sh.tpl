#!/bin/bash
# =============================================================================
# DEPLOYMENT STATE CHECKER & WATCHER
# =============================================================================
# Intelligently checks deployment state by comparing:
# - Latest GitHub commit on main/master branch
# - GitHub Actions workflow status
# - Currently deployed ECS image (tagged with commit SHA)
# - ECS task stability (running == desired, single deployment)
# - HTTP health check (GET /health returns 200)
#
# Both prod and dev environments have full ECS deployment tracking.
# Prod services (user-api, driver-api, messenger) deploy from main/master.
# Dev services (dev-user-api, dev-driver-api, dev-messenger) deploy from dev branch.
#
# States (both environments):
#   ✓ UP TO DATE     - Deployed, ECS stable, serving traffic
#   ⟳ STABILIZING    - Right SHA deployed but tasks still rolling/starting
#   ⟳ GITHUB CI      - GitHub Actions workflow is running
#   ⟳ ECS DEPLOYING  - ECS deployment in progress
#   ✗ NEEDS DEPLOY   - New commit exists but not deploying
#   ✗ FAILED         - GitHub Action or deployment failed
#
# Infrastructure (Terraform) tracking:
# - Pass "infrastructure", "terraform", or "infra" to check/watch Terraform workflow.
# - Uses GitHub Actions runs from {{GITHUB_ORG}}/infrastructure (Terraform workflow).
#
# Usage: ./check-deployment.sh [--env prod|dev|all] [--watch] [service1,service2,...]
# =============================================================================

set -e

# Configuration (rendered by cto-bootstrap)
CLUSTER="{{ECS_CLUSTER}}"
REGION="{{AWS_REGION}}"
POLL_INTERVAL=10
GITHUB_ORG="{{GITHUB_ORG}}"
ENV_FILTER="all"  # prod, dev, or all

# Service configuration (bash 3.x compatible - no associative arrays)
# Format: "ecs_service:repo_name:git_branch:env:ecr_tag_prefix"
#
# ecs_service:    ECS service name in the cluster
# repo_name:      GitHub repo name under GITHUB_ORG
# git_branch:     Branch to track ({{PROD_BRANCH}} for prod, {{DEV_BRANCH}} for dev)
# env:            prod or dev (controls display section and filtering)
# ecr_tag_prefix: "" for prod (tags: {sha}, latest), "dev-" for dev (tags: dev-{sha}, dev-latest)
SERVICES_CONFIG=(
{{SERVICES_CONFIG_LINES}}
)

DEV_BRANCH="{{DEV_BRANCH}}"
INFRASTRUCTURE_REPO="${GITHUB_ORG}/infrastructure"
TERRAFORM_WORKFLOW="Terraform"

# Get list of service names (optionally filtered by env)
get_service_names() {
    local filter_env="${1:-}"
    for config in "${SERVICES_CONFIG[@]}"; do
        local svc="${config%%:*}"
        if [[ -n "$filter_env" ]]; then
            local env
            env=$(get_service_env "$svc")
            [[ "$env" != "$filter_env" ]] && continue
        fi
        echo "$svc"
    done
}

# Parse a config field by position (0-indexed)
_get_config_field() {
    local service=$1
    local field_idx=$2
    for config in "${SERVICES_CONFIG[@]}"; do
        local svc="${config%%:*}"
        if [[ "$svc" == "$service" ]]; then
            local rest="$config"
            local i=0
            while [[ $i -lt $field_idx ]]; do
                rest="${rest#*:}"
                i=$((i + 1))
            done
            echo "${rest%%:*}"
            return
        fi
    done
    echo ""
}

# Get GitHub repo name for a service
get_service_repo() {
    _get_config_field "$1" 1
}

# Get git branch for a service
get_service_branch() {
    _get_config_field "$1" 2
}

# Get environment (prod or dev)
get_service_env() {
    _get_config_field "$1" 3
}

# Get ECR tag prefix ("" for prod, "dev-" for dev)
get_service_ecr_prefix() {
    _get_config_field "$1" 4
}

# Backward compat alias
get_service_prod_branch() {
    get_service_branch "$1"
}

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

# Status symbols
SYM_SUCCESS="✓"
SYM_DEPLOYING="⟳"
SYM_FAILED="✗"
SYM_PENDING="○"

# Verbose mode (set via --verbose)
VERBOSE=false

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}${SYM_SUCCESS}${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}${SYM_FAILED}${NC} $1"
}

log_verbose() {
    if $VERBOSE; then
        echo -e "${DIM}   [debug] $1${NC}" >&2
    fi
}

# Show header
show_header() {
    local env_label
    case "$ENV_FILTER" in
        prod) env_label="Production" ;;
        dev)  env_label="Development" ;;
        all)  env_label="All Environments" ;;
    esac
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}${WHITE}DEPLOYMENT STATE CHECKER${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              Cluster: ${YELLOW}${CLUSTER}${NC}  |  ${MAGENTA}${env_label}${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
# GitHub Functions
# =============================================================================

# Get latest commit SHA from GitHub branch
get_github_latest_sha() {
    local repo=$1
    local branch=$2
    
    gh api "repos/${GITHUB_ORG}/${repo}/commits/${branch}" \
        --jq '.sha' 2>/dev/null | head -c 40
}

# Get GitHub Actions workflow status for a commit
get_github_workflow_status() {
    local repo=$1
    local sha=$2
    
    local result
    result=$(gh api "repos/${GITHUB_ORG}/${repo}/actions/runs?head_sha=${sha}&per_page=1" \
        --jq '.workflow_runs[0] | {status: .status, conclusion: .conclusion, html_url: .html_url, name: .name, created_at: .created_at}' 2>/dev/null)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        echo '{"status": "not_found", "conclusion": null}'
    else
        echo "$result"
    fi
}

# Get number of commits dev is ahead of prod
get_commits_ahead() {
    local repo=$1
    local prod_branch=$2
    
    local result
    result=$(gh api "repos/${GITHUB_ORG}/${repo}/compare/${prod_branch}...${DEV_BRANCH}" \
        --jq '.ahead_by' 2>/dev/null)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "?"
    else
        echo "$result"
    fi
}

# Get short SHA
short_sha() {
    echo "${1:0:7}"
}

# =============================================================================
# AWS/ECS Functions
# =============================================================================

# Get currently deployed image tag from ECS
# Resolves "latest" and "dev-latest" to their commit SHA tags via ECR digest lookup.
get_deployed_image_tag() {
    local service=$1
    
    local task_def
    task_def=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$service" \
        --region "$REGION" \
        --query 'services[0].taskDefinition' \
        --output text 2>/dev/null)
    
    if [[ -z "$task_def" || "$task_def" == "None" ]]; then
        echo "unknown"
        return
    fi
    
    local image
    image=$(aws ecs describe-task-definition \
        --task-definition "$task_def" \
        --region "$REGION" \
        --query 'taskDefinition.containerDefinitions[0].image' \
        --output text 2>/dev/null)
    
    local tag="${image##*:}"
    
    # Resolve floating tags (latest, dev-latest) to the actual commit SHA tag
    if [[ "$tag" == "latest" || "$tag" == "dev-latest" ]]; then
        local repo
        repo=$(get_service_repo "$service")
        local ecr_prefix
        ecr_prefix=$(get_service_ecr_prefix "$service")
        
        local ecr_repo="{{ECR_NAMESPACE}}/${repo}"
        local digest
        digest=$(aws ecr describe-images \
            --repository-name "$ecr_repo" \
            --image-ids imageTag="$tag" \
            --region "$REGION" \
            --query 'imageDetails[0].imageDigest' \
            --output text 2>/dev/null)
        
        if [[ -n "$digest" && "$digest" != "None" ]]; then
            local sha_tag
            # Filter out floating tags, keep only SHA tags matching the right prefix
            sha_tag=$(aws ecr describe-images \
                --repository-name "$ecr_repo" \
                --region "$REGION" \
                --query "imageDetails[?imageDigest=='${digest}'].imageTags[]" \
                --output text 2>/dev/null | tr '\t' '\n' | grep -v 'latest' | grep "^${ecr_prefix}" | head -1)
            
            # Strip the ecr_prefix to get bare SHA (dev-abc123 → abc123)
            if [[ -n "$sha_tag" ]]; then
                echo "${sha_tag#$ecr_prefix}"
                return
            fi
        fi
    fi
    
    echo "$tag"
}

# Check if ECS deployment is in progress
is_ecs_deploying() {
    local service=$1
    local deployment_count
    deployment_count=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$service" \
        --region "$REGION" \
        --query 'services[0].deployments | length(@)' \
        --output text 2>/dev/null)
    
    [[ "$deployment_count" != "1" ]]
}

# Get ECS deployment details
get_ecs_deployment_info() {
    local service=$1
    aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$service" \
        --region "$REGION" \
        --query 'services[0].{
            running: runningCount,
            desired: desiredCount,
            pending: pendingCount,
            deployments: deployments[*].{
                status: status,
                running: runningCount,
                desired: desiredCount,
                rollout: rolloutState
            }
        }' \
        --output json 2>/dev/null
}

# Check if ECS deployment is fully stable (1 deployment, running == desired)
is_ecs_stable() {
    local service=$1
    local info
    info=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$service" \
        --region "$REGION" \
        --query 'services[0].{dc: length(deployments), running: runningCount, desired: desiredCount}' \
        --output json 2>/dev/null)
    
    local dc running desired
    dc=$(echo "$info" | jq -r '.dc')
    running=$(echo "$info" | jq -r '.running')
    desired=$(echo "$info" | jq -r '.desired')
    
    log_verbose "ECS stable check: deployments=$dc, running=$running, desired=$desired"
    
    [[ "$dc" == "1" && "$running" == "$desired" && "$running" != "0" ]]
}

# Health checks are done internally by ECS target groups (GET /health on the
# container port). No public health URL is needed — the ALB doesn't expose
# /health paths. ECS task stability (is_ecs_stable) is the source of truth.

# =============================================================================
# State Determination — Production
# =============================================================================

get_deployment_state() {
    local service=$1
    local repo
    repo=$(get_service_repo "$service")
    local branch
    branch=$(get_service_branch "$service")
    
    log_verbose "Checking $service (repo: $repo, branch: $branch)"
    
    local github_sha
    github_sha=$(get_github_latest_sha "$repo" "$branch")
    
    if [[ -z "$github_sha" ]]; then
        log_verbose "Failed to fetch GitHub commit for $repo/$branch"
        echo "ERROR|Could not fetch GitHub commit"
        return
    fi
    
    log_verbose "GitHub latest SHA: $github_sha"
    
    local deployed_sha
    deployed_sha=$(get_deployed_image_tag "$service")
    log_verbose "ECS deployed tag: $deployed_sha"
    
    local ecs_deploying
    ecs_deploying=$(is_ecs_deploying "$service" && echo "true" || echo "false")
    log_verbose "ECS deploying: $ecs_deploying"
    
    local workflow_info
    workflow_info=$(get_github_workflow_status "$repo" "$github_sha")
    local workflow_status
    local workflow_conclusion
    workflow_status=$(echo "$workflow_info" | jq -r '.status // "not_found"')
    workflow_conclusion=$(echo "$workflow_info" | jq -r '.conclusion // "null"')
    log_verbose "Workflow status: $workflow_status, conclusion: $workflow_conclusion"
    
    if [[ "$github_sha" == "$deployed_sha"* ]] || [[ "$deployed_sha" == "$github_sha"* ]]; then
        if [[ "$ecs_deploying" == "true" ]]; then
            log_verbose "Decision: STABILIZING (SHA match but ECS still rolling)"
            echo "STABILIZING|$(short_sha "$github_sha")|tasks rolling"
        elif ! is_ecs_stable "$service"; then
            log_verbose "Decision: STABILIZING (SHA match but tasks not ready)"
            echo "STABILIZING|$(short_sha "$github_sha")|tasks starting"
        else
            log_verbose "Decision: UP_TO_DATE (SHA match + ECS stable)"
            echo "UP_TO_DATE|$(short_sha "$github_sha")|deployed"
        fi
    elif [[ "$ecs_deploying" == "true" ]]; then
        log_verbose "Decision: ECS_DEPLOYING"
        echo "ECS_DEPLOYING|$(short_sha "$github_sha")|$(short_sha "$deployed_sha")"
    elif [[ "$workflow_status" == "in_progress" || "$workflow_status" == "queued" || "$workflow_status" == "waiting" ]]; then
        log_verbose "Decision: GITHUB_CI ($workflow_status)"
        echo "GITHUB_CI|$(short_sha "$github_sha")|$workflow_status"
    elif [[ "$workflow_conclusion" == "failure" || "$workflow_conclusion" == "cancelled" ]]; then
        log_verbose "Decision: FAILED ($workflow_conclusion)"
        echo "FAILED|$(short_sha "$github_sha")|$workflow_conclusion"
    elif [[ "$workflow_status" == "not_found" ]]; then
        log_verbose "Decision: PENDING (no workflow found)"
        echo "PENDING|$(short_sha "$github_sha")|awaiting CI"
    else
        log_verbose "Decision: NEEDS_DEPLOY (workflow done but SHA mismatch)"
        echo "NEEDS_DEPLOY|$(short_sha "$github_sha")|$(short_sha "$deployed_sha")"
    fi
}

# get_dev_branch_state removed — dev services now have full ECS deployment
# tracking via get_deployment_state (same as prod).

# =============================================================================
# Terraform / Infrastructure Functions
# =============================================================================

# Get Terraform workflow run state. Returns: STATE|run_id|detail
get_terraform_state() {
    local result
    result=$(gh api "repos/${INFRASTRUCTURE_REPO}/actions/runs?per_page=10" \
        --jq '[.workflow_runs[] | select(.name == "Terraform")][0] | {id, status, conclusion, html_url}' 2>/dev/null)

    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "PENDING|—|no run found"
        return
    fi

    local run_id status conclusion
    run_id=$(echo "$result" | jq -r '.id // empty')
    status=$(echo "$result" | jq -r '.status // "unknown"')
    conclusion=$(echo "$result" | jq -r '.conclusion // "null"')

    if [[ "$status" == "in_progress" || "$status" == "queued" || "$status" == "waiting" ]]; then
        echo "GITHUB_CI|${run_id}|${status}"
    elif [[ "$conclusion" == "success" ]]; then
        echo "UP_TO_DATE|${run_id}|success"
    elif [[ "$conclusion" == "failure" || "$conclusion" == "cancelled" ]]; then
        echo "FAILED|${run_id}|${conclusion}"
    else
        echo "PENDING|${run_id}|${status}"
    fi
}

format_terraform_state() {
    local state=$1
    local detail1=$2
    local detail2=$3

    case "$state" in
        "UP_TO_DATE")
            echo -e "${GREEN}${SYM_SUCCESS} UP TO DATE${NC}     ${GRAY}[run ${detail1}] ${detail2}${NC}"
            ;;
        "GITHUB_CI")
            echo -e "${BLUE}${SYM_DEPLOYING} GITHUB CI${NC}      ${GRAY}[run ${detail1}] ${detail2}${NC}"
            ;;
        "PENDING")
            echo -e "${CYAN}${SYM_PENDING} PENDING${NC}        ${GRAY}${detail2}${NC}"
            ;;
        "FAILED")
            echo -e "${RED}${SYM_FAILED} FAILED${NC}         ${GRAY}[run ${detail1}] ${detail2}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}${SYM_FAILED} ERROR${NC}          ${GRAY}${detail1}${NC}"
            ;;
        *)
            echo -e "${GRAY}? UNKNOWN${NC}        ${GRAY}${detail1}${NC}"
            ;;
    esac
}

# =============================================================================
# Display Functions
# =============================================================================

format_state() {
    local state=$1
    local detail1=$2
    local detail2=$3
    
    case "$state" in
        "UP_TO_DATE")
            echo -e "${GREEN}${SYM_SUCCESS} UP TO DATE${NC}     ${GRAY}[${detail1}] serving traffic${NC}"
            ;;
        "STABILIZING")
            echo -e "${YELLOW}${SYM_DEPLOYING} STABILIZING${NC}    ${GRAY}[${detail1}] ${detail2}${NC}"
            ;;
        "HEALTH_CHECK")
            echo -e "${YELLOW}${SYM_DEPLOYING} HEALTH CHECK${NC}   ${GRAY}[${detail1}] ${detail2}${NC}"
            ;;
        "ECS_DEPLOYING")
            echo -e "${YELLOW}${SYM_DEPLOYING} ECS DEPLOYING${NC}  ${GRAY}[${detail1} → ${detail2}]${NC}"
            ;;
        "GITHUB_CI")
            echo -e "${BLUE}${SYM_DEPLOYING} GITHUB CI${NC}      ${GRAY}[${detail1}] ${detail2}${NC}"
            ;;
        "PENDING")
            echo -e "${CYAN}${SYM_PENDING} PENDING${NC}        ${GRAY}[${detail1}] ${detail2}${NC}"
            ;;
        "NEEDS_DEPLOY")
            echo -e "${RED}${SYM_FAILED} NEEDS DEPLOY${NC}   ${GRAY}[${detail1} vs ${detail2}]${NC}"
            ;;
        "FAILED")
            echo -e "${RED}${SYM_FAILED} FAILED${NC}         ${GRAY}[${detail1}] ${detail2}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}${SYM_FAILED} ERROR${NC}          ${GRAY}${detail1}${NC}"
            ;;
        *)
            echo -e "${GRAY}? UNKNOWN${NC}        ${GRAY}${detail1}${NC}"
            ;;
    esac
}

# Show detailed status for a service (returns state via global variable)
LAST_STATE=""
show_service_status() {
    local service=$1
    local state_info
    state_info=$(get_deployment_state "$service")
    
    local state="${state_info%%|*}"
    local rest="${state_info#*|}"
    local detail1="${rest%%|*}"
    local detail2="${rest#*|}"
    
    local formatted
    formatted=$(format_state "$state" "$detail1" "$detail2")
    
    printf "  %-15s %s\n" "${CYAN}${service}${NC}" "$formatted"
    
    LAST_STATE="$state"
}

# Get the base service name (dev-user-api → user-api) for display purposes
get_base_service_name() {
    local service=$1
    echo "${service#dev-}"
}

# Show success banner
show_success_banner() {
    local service=$1
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                          ║${NC}"
    echo -e "${GREEN}║   ██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗███████╗██████╗      ║${NC}"
    echo -e "${GREEN}║   ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝██╔════╝██╔══██╗     ║${NC}"
    echo -e "${GREEN}║   ██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝ █████╗  ██║  ██║     ║${NC}"
    echo -e "${GREEN}║   ██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝  ██╔══╝  ██║  ██║     ║${NC}"
    echo -e "${GREEN}║   ██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║   ███████╗██████╔╝     ║${NC}"
    echo -e "${GREEN}║   ╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝   ╚══════╝╚═════╝      ║${NC}"
    echo -e "${GREEN}║                                                                          ║${NC}"
    echo -e "${GREEN}║                        ${WHITE}${BOLD}✓ ${service} is live!${NC}${GREEN}                           ║${NC}"
    echo -e "${GREEN}║                                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
# Main Logic
# =============================================================================

check_services() {
    local services=("$@")

    local any_deploying=false
    local any_failed=false

    # Infrastructure section (Terraform workflow)
    if [[ " ${services[*]} " =~ " infrastructure " ]]; then
        echo -e "${WHITE}${BOLD}INFRASTRUCTURE${NC} ${GRAY}(Terraform apply on push to main)${NC}"
        echo ""

        local state_info
        state_info=$(get_terraform_state)
        local state="${state_info%%|*}"
        local rest="${state_info#*|}"
        local detail1="${rest%%|*}"
        local detail2="${rest#*|}"

        printf "  %-15s %s\n" "${CYAN}infrastructure${NC}" "$(format_terraform_state "$state" "$detail1" "$detail2")"
        echo ""

        case "$state" in
            "GITHUB_CI"|"PENDING")
                any_deploying=true
                ;;
            "FAILED")
                any_failed=true
                ;;
        esac
    fi

    local ecs_services=()
    for s in "${services[@]}"; do
        [[ "$s" != "infrastructure" ]] && ecs_services+=("$s")
    done
    services=("${ecs_services[@]}")
    [[ ${#services[@]} -eq 0 ]] && { $any_deploying && return 2 || $any_failed && return 1 || return 0; }

    # Production section
    if [[ "$ENV_FILTER" == "prod" || "$ENV_FILTER" == "all" ]]; then
        local has_prod=false
        for service in "${services[@]}"; do
            [[ "$(get_service_env "$service")" == "prod" ]] && has_prod=true && break
        done
        
        if $has_prod; then
            echo -e "${WHITE}${BOLD}PRODUCTION${NC} ${GRAY}(main/master → ECS prod services)${NC}"
            echo ""
            
            for service in "${services[@]}"; do
                local svc_env
                svc_env=$(get_service_env "$service")
                [[ "$svc_env" != "prod" ]] && continue
                
                show_service_status "$service"
                
                case "$LAST_STATE" in
                    "ECS_DEPLOYING"|"GITHUB_CI"|"PENDING"|"STABILIZING"|"HEALTH_CHECK")
                        any_deploying=true
                        ;;
                    "FAILED"|"NEEDS_DEPLOY")
                        any_failed=true
                        ;;
                esac
            done
            
            echo ""
        fi
    fi
    
    # Dev section — full deployment tracking (same as prod, different ECS services)
    if [[ "$ENV_FILTER" == "dev" || "$ENV_FILTER" == "all" ]]; then
        local has_dev=false
        for service in "${services[@]}"; do
            [[ "$(get_service_env "$service")" == "dev" ]] && has_dev=true && break
        done
        
        if $has_dev; then
            echo -e "${WHITE}${BOLD}DEV${NC} ${GRAY}({{DEV_BRANCH}} branch → ECS dev services)${NC}"
            echo ""
            
            for service in "${services[@]}"; do
                local svc_env
                svc_env=$(get_service_env "$service")
                [[ "$svc_env" != "dev" ]] && continue
                
                show_service_status "$service"
                
                case "$LAST_STATE" in
                    "ECS_DEPLOYING"|"GITHUB_CI"|"PENDING"|"STABILIZING"|"HEALTH_CHECK")
                        any_deploying=true
                        ;;
                    "FAILED"|"NEEDS_DEPLOY")
                        any_failed=true
                        ;;
                esac
            done
            
            echo ""
        fi
    fi
    
    # Return status for scripting
    if $any_deploying; then
        return 2  # In progress
    elif $any_failed; then
        return 1  # Failed or needs attention
    else
        return 0  # All good
    fi
}

# Watch mode - continuously monitor until all deployments complete
watch_services() {
    local services=("$@")
    local start_time=$(date +%s)
    local completed=()
    local spin_idx=0
    local SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    echo -e "${WHITE}Watching ${#services[@]} service(s) — deployments...${NC}"
    echo -e "${DIM}Press Ctrl+C to exit${NC}"
    echo ""

    # Initial display
    for service in "${services[@]}"; do
        echo ""  # Placeholder line
    done

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local all_complete=true

        # Move cursor up to redraw
        printf "\033[%dA" "${#services[@]}"

        for service in "${services[@]}"; do
            # Skip if already completed
            if [[ " ${completed[*]} " =~ " ${service} " ]]; then
                printf "  ${GREEN}${SYM_SUCCESS}${NC} %-15s ${GREEN}DEPLOYED${NC}                                    \n" "$service"
                continue
            fi

            # Get current state (infrastructure uses Terraform workflow; others use ECS)
            local state_info
            if [[ "$service" == "infrastructure" ]]; then
                state_info=$(get_terraform_state)
            else
                state_info=$(get_deployment_state "$service")
            fi

            local state="${state_info%%|*}"
            local rest="${state_info#*|}"
            local detail1="${rest%%|*}"
            local detail2="${rest#*|}"
            
            case "$state" in
                "UP_TO_DATE")
                    completed+=("$service")
                    if [[ "$service" == "infrastructure" ]]; then
                        printf "  ${GREEN}${SYM_SUCCESS}${NC} %-15s ${GREEN}APPLIED${NC} [run %s]                     \n" "$service" "$detail1"
                    else
                        printf "  ${GREEN}${SYM_SUCCESS}${NC} %-15s ${GREEN}LIVE${NC} [%s] serving traffic                \n" "$service" "$detail1"
                    fi
                    (show_success_banner "$service") &
                    ;;
                "STABILIZING")
                    all_complete=false
                    local spin="${SPINNER[$spin_idx]}"
                    printf "  ${YELLOW}${spin}${NC} %-15s ${YELLOW}STABILIZING${NC} [%s] %s %ds            \n" "$service" "$detail1" "$detail2" "$elapsed"
                    ;;
                "HEALTH_CHECK")
                    all_complete=false
                    local spin="${SPINNER[$spin_idx]}"
                    printf "  ${MAGENTA}${spin}${NC} %-15s ${MAGENTA}HEALTH CHECK${NC} [%s] waiting for /health %ds  \n" "$service" "$detail1" "$elapsed"
                    ;;
                "ECS_DEPLOYING")
                    all_complete=false
                    local spin="${SPINNER[$spin_idx]}"
                    printf "  ${YELLOW}${spin}${NC} %-15s ${YELLOW}ECS DEPLOYING${NC} [%s] %ds                  \n" "$service" "$detail1" "$elapsed"
                    ;;
                "GITHUB_CI"|"PENDING")
                    all_complete=false
                    local spin="${SPINNER[$spin_idx]}"
                    printf "  ${BLUE}${spin}${NC} %-15s ${BLUE}GITHUB CI${NC} [%s] %s %ds                  \n" "$service" "$detail1" "$detail2" "$elapsed"
                    ;;
                "FAILED")
                    printf "  ${RED}${SYM_FAILED}${NC} %-15s ${RED}FAILED${NC} [%s] %s                       \n" "$service" "$detail1" "$detail2"
                    ;;
                "NEEDS_DEPLOY")
                    printf "  ${RED}${SYM_FAILED}${NC} %-15s ${RED}NEEDS DEPLOY${NC} [%s vs %s]              \n" "$service" "$detail1" "$detail2"
                    ;;
                *)
                    all_complete=false
                    printf "  ${GRAY}?${NC} %-15s ${GRAY}CHECKING...${NC}                              \n" "$service"
                    ;;
            esac
        done
        
        spin_idx=$(( (spin_idx + 1) % ${#SPINNER[@]} ))
        
        if $all_complete || [[ ${#completed[@]} -eq ${#services[@]} ]]; then
            echo ""
            echo -e "${GREEN}${BOLD}All deployments complete!${NC}"
            echo ""
            
            if command -v afplay &> /dev/null; then
                afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
            fi
            
            break
        fi
        
        sleep "$POLL_INTERVAL"
    done
}

# Parse service selection
# If a base name is given (e.g. "user-api"), expands to both prod and dev variants.
# If a specific service is given (e.g. "dev-user-api"), uses that directly.
select_services() {
    local services_arg=$1
    local selected=()
    
    if [[ -n "$services_arg" ]]; then
        IFS=',' read -ra raw_selection <<< "$services_arg"
        for raw in "${raw_selection[@]}"; do
            raw=$(echo "$raw" | tr -d ' ')
            # Strip leading -- (e.g. --user-api → user-api) so accidental flag-like args work
            [[ "$raw" == --* ]] && raw="${raw#--}"

            # Infrastructure / Terraform
            if [[ "$raw" == "infrastructure" || "$raw" == "terraform" || "$raw" == "infra" ]]; then
                selected+=("infrastructure")
                continue
            fi

            # Check if this is a dev-prefixed service (e.g. dev-user-api)
            local is_dev_specific=false
            if [[ "$raw" == dev-* ]]; then
                for config in "${SERVICES_CONFIG[@]}"; do
                    local svc="${config%%:*}"
                    if [[ "$svc" == "$raw" ]]; then
                        is_dev_specific=true
                        selected+=("$raw")
                        break
                    fi
                done
                $is_dev_specific && continue
            fi

            # Expand base name to include both prod and dev variants
            # e.g. "user-api" → ["user-api", "dev-user-api"]
            local found=false
            for config in "${SERVICES_CONFIG[@]}"; do
                local svc="${config%%:*}"
                local base="${svc#dev-}"
                if [[ "$base" == "$raw" ]]; then
                    selected+=("$svc")
                    found=true
                fi
            done

            # If nothing matched, pass through as-is (will fail gracefully later)
            if ! $found; then
                selected+=("$raw")
            fi
        done
    else
        # Interactive menu — show base service names, expand based on env filter
        local base_names=()
        for config in "${SERVICES_CONFIG[@]}"; do
            local svc="${config%%:*}"
            local env
            env=$(_get_config_field "$svc" 3)
            [[ "$env" != "prod" ]] && continue
            base_names+=("$svc")
        done
        
        echo -e "${WHITE}Available services:${NC}" > /dev/tty
        echo "" > /dev/tty
        
        for i in "${!base_names[@]}"; do
            echo -e "  ${CYAN}$((i+1))${NC}) ${base_names[$i]}" > /dev/tty
        done
        echo -e "  ${CYAN}$(( ${#base_names[@]} + 1 ))${NC}) infrastructure (Terraform)" > /dev/tty
        echo -e "  ${CYAN}a${NC}) All ECS services" > /dev/tty
        echo "" > /dev/tty

        read -p "Select services (e.g., 1,2 or 'a' for all): " selection < /dev/tty

        local chosen_bases=()
        if [[ "$selection" == "a" || "$selection" == "A" ]]; then
            chosen_bases=("${base_names[@]}")
        else
            IFS=',' read -ra indices <<< "$selection"
            for idx in "${indices[@]}"; do
                idx=$(echo "$idx" | tr -d ' ')
                if [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -eq $((${#base_names[@]} + 1)) ]]; then
                    selected+=("infrastructure")
                elif [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -ge 1 ]] && [[ $idx -le ${#base_names[@]} ]]; then
                    chosen_bases+=("${base_names[$((idx-1))]}")
                fi
            done
        fi
        
        # Expand base names to include both prod and dev variants
        for base in "${chosen_bases[@]}"; do
            for config in "${SERVICES_CONFIG[@]}"; do
                local svc="${config%%:*}"
                local svc_base="${svc#dev-}"
                if [[ "$svc_base" == "$base" ]]; then
                    selected+=("$svc")
                fi
            done
        done
    fi
    
    echo "${selected[@]}"
}

# Main
main() {
    local watch_mode=false
    local services_arg=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --watch|-w)
                watch_mode=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --env)
                ENV_FILTER="$2"
                if [[ "$ENV_FILTER" != "prod" && "$ENV_FILTER" != "dev" && "$ENV_FILTER" != "all" ]]; then
                    log_error "Invalid environment: $ENV_FILTER (expected: prod, dev, all)"
                    exit 1
                fi
                shift 2
                ;;
            --dev)
                ENV_FILTER="dev"
                shift
                ;;
            --prod)
                ENV_FILTER="prod"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [service1,service2,...]"
                echo ""
                echo "Checks deployment state by comparing GitHub commits, CI status,"
                echo "and ECS deployed images. Also shows dev branch CI status."
                echo ""
                echo "Options:"
                echo "  --env ENV       Environment to check: prod, dev, all (default: all)"
                echo "  --prod          Shorthand for --env prod"
                echo "  --dev           Shorthand for --env dev"
                echo "  --watch, -w     Watch mode: continuously monitor prod until complete"
                echo "  --verbose, -v   Verbose output with debug information"
                echo "  --help, -h      Show this help"
                echo ""
                echo "Services: $(get_service_names | tr '\n' ' ') infrastructure"
                echo ""
                echo "States (both prod and dev):"
                echo "  ${SYM_SUCCESS} UP TO DATE     - Deployed, ECS stable, serving traffic"
                echo "  ${SYM_DEPLOYING} STABILIZING    - Right SHA but tasks still rolling/starting"
                echo "  ${SYM_DEPLOYING} GITHUB CI      - GitHub Actions workflow running"
                echo "  ${SYM_DEPLOYING} ECS DEPLOYING  - ECS deployment in progress"
                echo "  ${SYM_PENDING} PENDING        - Awaiting CI to start"
                echo "  ${SYM_FAILED} NEEDS DEPLOY   - New commit not deploying"
                echo "  ${SYM_FAILED} FAILED         - GitHub Action failed"
                echo ""
                echo "Examples:"
                echo "  $0                           # Check all services, both environments"
                echo "  $0 --prod                    # Production only"
                echo "  $0 --dev                     # Dev environment only"
                echo "  $0 --watch                   # Watch all deployments"
                echo "  $0 user-api                  # Check user-api (both prod + dev)"
                echo "  $0 dev-user-api              # Check only dev user-api"
                echo "  $0 --prod -w user-api        # Watch single service production"
                echo "  $0 -v user-api               # Verbose debug output"
                echo "  $0 infrastructure --watch    # Watch Terraform apply (infra repo)"
                echo ""
                echo "Behavior:"
                echo "  - Default shows both prod and dev status for all services"
                echo "  - Passing 'user-api' checks both prod (user-api) and dev (dev-user-api)"
                echo "  - Passing 'dev-user-api' checks only the dev service"
                echo "  - Both environments have full ECS deployment tracking"
                echo "  - If any deployment is in progress, auto-switches to watch mode"
                echo "  - Exit codes: 0=up-to-date, 1=failed/needs-deploy, 2=in-progress"
                exit 0
                ;;
            *)
                services_arg=$1
                shift
                ;;
        esac
    done
    
    # Check dependencies
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is required. Install with: brew install gh"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required. Install with: brew install jq"
        exit 1
    fi
    
    # Check GitHub authentication
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    
    # AWS is only required for prod checks
    if [[ "$ENV_FILTER" == "prod" || "$ENV_FILTER" == "all" ]]; then
        if ! command -v aws &> /dev/null; then
            log_error "AWS CLI is required for production checks. Install with: brew install awscli"
            exit 1
        fi
        
        if ! aws sts get-caller-identity &>/dev/null; then
            log_error "AWS credentials not configured. Run: aws configure"
            exit 1
        fi
    fi
    
    show_header
    
    # Select services
    local selected
    read -ra selected <<< "$(select_services "$services_arg")"
    
    if [[ ${#selected[@]} -eq 0 ]]; then
        log_error "No services selected. Exiting."
        exit 1
    fi
    
    echo ""
    echo -e "${WHITE}Selected: ${CYAN}${selected[*]}${NC}"
    echo ""
    
    # Check initial state to decide mode
    if ! $watch_mode; then
        local any_deploying=false

        for service in "${selected[@]}"; do
            local state_info
            if [[ "$service" == "infrastructure" ]]; then
                state_info=$(get_terraform_state)
            else
                state_info=$(get_deployment_state "$service")
            fi
            local state="${state_info%%|*}"

            case "$state" in
                "ECS_DEPLOYING"|"GITHUB_CI"|"PENDING"|"STABILIZING"|"HEALTH_CHECK")
                    any_deploying=true
                    break
                    ;;
            esac
        done

        if $any_deploying; then
            echo -e "${YELLOW}Deployment in progress detected - switching to watch mode${NC}"
            echo ""
            watch_mode=true
        fi
    fi
    
    # Run appropriate mode
    if $watch_mode; then
        watch_services "${selected[@]}"
    else
        check_services "${selected[@]}"
    fi
}

# Run
main "$@"
