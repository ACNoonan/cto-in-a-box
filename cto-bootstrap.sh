#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="${SCRIPT_DIR}/cto-templates"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

slugify() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "$value"
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

prompt() {
  local label="$1"
  local default_value="${2:-}"
  local answer=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " answer
    answer="$(trim "${answer:-$default_value}")"
  else
    read -r -p "$label: " answer
    answer="$(trim "$answer")"
  fi

  printf '%s' "$answer"
}

prompt_yes_no() {
  local label="$1"
  local default_value="${2:-y}"
  local answer=""
  local normalized=""

  while true; do
    read -r -p "$label [${default_value}]: " answer
    answer="$(trim "${answer:-$default_value}")"
    normalized="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      y|yes) printf 'true'; return ;;
      n|no) printf 'false'; return ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

phase_name() {
  case "$1" in
    0) printf 'local-mvp' ;;
    1) printf 'deployed-demo' ;;
    2) printf 'production-baseline' ;;
    3) printf 'scale-and-expansion' ;;
    4) printf 'reusable-platform' ;;
    *) printf 'custom' ;;
  esac
}

phase_title() {
  case "$1" in
    0) printf 'Phase 0 - Local MVP' ;;
    1) printf 'Phase 1 - Deployed Demo' ;;
    2) printf 'Phase 2 - Production Baseline' ;;
    3) printf 'Phase 3 - Scale And Expansion' ;;
    4) printf 'Phase 4 - Reusable Platform' ;;
    *) printf 'Unknown phase' ;;
  esac
}

next_phase_id() {
  local current="$1"
  if (( current >= 4 )); then
    printf ''
  else
    printf '%s' "$(( current + 1 ))"
  fi
}

choose_phase() {
  local answer=""
  echo "Select the current phase to scaffold:" >&2
  echo "  0) Local MVP: workspace, first domain model, local-only or lightly shared development" >&2
  echo "  1) Deployed demo: first shared environment, first real deploy path" >&2
  echo "  2) Production baseline: protected production flow, guardrails, ops scripts" >&2
  echo "  3) Scale and expansion: more surfaces, contracts, internal tools, specialized services" >&2
  echo "  4) Reusable platform: reusable templates, cross-cutting systems, standardization" >&2
  while true; do
    read -r -p "Phase [0]: " answer
    answer="$(trim "${answer:-0}")"
    case "$answer" in
      0|1|2|3|4)
        printf '%s' "$answer"
        return
        ;;
      *)
        echo "Choose 0, 1, 2, 3, or 4." >&2
        ;;
    esac
  done
}

phase_recommendation() {
  case "$1" in
    0) printf 'Next phase focus: stand up the first shared deployed environment on the default AWS, Terraform, and ECS path.' ;;
    1) printf 'Next phase focus: make production boring with branch protection, deploy checks, and ops scripts.' ;;
    2) printf 'Next phase focus: expand surfaces and services only where demand is real, then add contract discipline.' ;;
    3) printf 'Next phase focus: package the proven operating model into reusable templates and starter kits.' ;;
    4) printf 'Next phase focus: keep tightening templates and only add complexity when repeated use proves it belongs.' ;;
    *) printf 'Next phase focus: define the next bottleneck before expanding the system.' ;;
  esac
}

phase_default_environments() {
  case "$1" in
    0) printf 'local' ;;
    1) printf 'dev,demo' ;;
    2) printf 'dev,prod' ;;
    3|4) printf 'dev,prod,demo' ;;
    *) printf 'dev,prod' ;;
  esac
}

csv_to_array() {
  local raw="$1"
  local item=""
  local -a cleaned=()
  local -a parts=()
  if [[ -z "$raw" ]]; then
    return
  fi
  IFS=',' read -r -a parts <<< "$raw" || true
  for item in "${parts[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && cleaned+=("$item")
  done
  printf '%s\n' "${cleaned[@]}"
}

csv_to_json_array() {
  local raw="$1"
  local result=""
  local item=""
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    [[ -n "$result" ]] && result+=", "
    result+="\"$(json_escape "$item")\""
  done < <(csv_to_array "$raw")
  printf '[%s]' "$result"
}

array_to_inline() {
  local fallback="$1"
  shift
  if [[ $# -eq 0 ]]; then
    printf '%s' "$fallback"
    return
  fi
  local joined=""
  local item=""
  for item in "$@"; do
    [[ -n "$joined" ]] && joined+=", "
    joined+="$item"
  done
  printf '%s' "$joined"
}

array_to_bullets() {
  local fallback="$1"
  shift
  if [[ $# -eq 0 ]]; then
    printf '%s' "$fallback"
    return
  fi
  local item=""
  for item in "$@"; do
    printf -- '- `%s`\n' "$item"
  done
}

append_unique() {
  local value="$1"
  local existing=""
  for existing in "${repo_names[@]:-}"; do
    [[ "$existing" == "$value" ]] && return
  done
  repo_names+=("$value")
}

bool_string() {
  if [[ "$1" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

render_template_file() {
  local template_path="$1"
  local output_path="$2"
  TEMPLATE_PATH="$template_path" OUTPUT_PATH="$output_path" python3 - <<'PY'
import os
from pathlib import Path

template_path = Path(os.environ["TEMPLATE_PATH"])
output_path = Path(os.environ["OUTPUT_PATH"])
content = template_path.read_text()

for key, value in os.environ.items():
    if key.startswith("CTO_"):
        content = content.replace("{{" + key[4:] + "}}", value)

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(content)
PY
  generated_files+=("$output_path")
}

echo ""
echo "CTO in a box bootstrap"
echo "This version writes a manifest and can render starter workspace templates."
echo "Default platform profile: AWS + Terraform + ECS unless you intentionally override it later."
echo "It does not create GitHub repos, AWS resources, or secrets."
echo ""

project_name="$(prompt "Project name")"
default_slug="$(slugify "$project_name")"
project_slug="$(prompt "Project slug" "$default_slug")"
workspace_name="$(prompt "Workspace folder name" "$project_slug")"
current_phase="$(choose_phase)"
phase_slug="$(phase_name "$current_phase")"
phase_title_text="$(phase_title "$current_phase")"
next_phase="$(next_phase_id "$current_phase")"
if [[ -n "$next_phase" ]]; then
  next_phase_title_text="$(phase_title "$next_phase")"
else
  next_phase_title_text="None"
fi
phase_recommendation_text="$(phase_recommendation "$current_phase")"
default_environments="$(phase_default_environments "$current_phase")"
aws_region="$(prompt "Primary AWS region for the default platform profile" "eu-south-2")"
github_org="$(prompt "GitHub org or user (for ops scripts)" "$project_slug")"
dev_branch="$(prompt "Default working branch" "dev")"
prod_branch="$(prompt "Default production branch" "main")"
ecs_cluster="$(prompt "ECS cluster name (used once deployed)" "${project_slug}-cluster")"
ecs_log_group="$(prompt "ECS CloudWatch log group (used once deployed)" "/ecs/${project_slug}")"
waf_log_group="$(prompt "WAF log group (used once deployed)" "aws-waf-logs-${project_slug}")"
vpc_flow_log_group="$(prompt "VPC flow log group (used once deployed)" "/aws/vpc/${project_slug}-flow-logs")"
ecr_namespace="$(prompt "ECR repo namespace prefix (used once deployed)" "$project_slug")"
expo_account_slug="$(prompt "Expo account slug (mobile only; leave blank if N/A)" "$project_slug")"
environments="$(prompt "Environments (comma separated)" "$default_environments")"

# Strategic DDD lens — see docs/ddd-primer.md for the concepts behind these prompts.
echo ""
echo "Domain (strategic DDD lens — see docs/ddd-primer.md)"
core_domain_name="$(prompt "Core domain name (what this product is trying to be excellent at)" "$project_name")"
core_domain_description="$(prompt "Core domain — one-sentence description")"

supporting_subdomains=""
bounded_contexts=""
ubiquitous_language=""
if (( current_phase >= 1 )); then
  supporting_subdomains="$(prompt "Supporting subdomains in scope now (comma separated, blank for none)")"
  bounded_contexts="$(prompt "Expected bounded contexts at this phase (comma separated, blank for none)")"
  ubiquitous_language="$(prompt "Seed glossary terms (comma separated, blank to fill in later)")"
fi

backend_services="$(prompt "Backend services in scope for this phase (comma separated, blank for none)" "${project_slug}-api")"

portal_apps=""
web_repo_name=""
portal_apps="$(prompt "Web apps or portals in scope for this phase (comma separated, blank for none)")"
if [[ -n "$(trim "$portal_apps")" ]]; then
  web_repo_name="$(prompt "Web repo name" "web")"
fi

include_mobile="false"
mobile_apps=""
if (( current_phase >= 1 )); then
  include_mobile="$(prompt_yes_no "Include mobile apps in this phase?" "n")"
  if [[ "$include_mobile" == "true" ]]; then
    mobile_apps="$(prompt "Mobile app names (comma separated)")"
  fi
fi

if (( current_phase == 0 )); then
  include_infra="$(prompt_yes_no "Include an infrastructure repo now? (recommended once you move beyond local MVP)" "n")"
else
  include_infra="true"
fi

if (( current_phase >= 2 )); then
  if (( current_phase >= 3 )); then
    automations_default="y"
  else
    automations_default="n"
  fi
  include_automations="$(prompt_yes_no "Include an automations repo in this phase?" "$automations_default")"
else
  include_automations="false"
fi

include_internal_tools="false"
if (( current_phase >= 3 )); then
  include_internal_tools="$(prompt_yes_no "Include internal tools or operations dashboard in this phase?" "y")"
fi

include_platform_api="false"
platform_api_name=""
if (( current_phase >= 4 )); then
  include_platform_api="$(prompt_yes_no "Include a dedicated platform API in this phase? (flags, translation, remote config)" "y")"
  if [[ "$include_platform_api" == "true" ]]; then
    platform_api_name="$(prompt "Platform API repo name" "platform-api")"
  fi
fi

include_realtime_service="false"
realtime_service_name=""
if (( current_phase >= 3 )); then
  include_realtime_service="$(prompt_yes_no "Include a dedicated realtime or messaging service in this phase?" "n")"
  if [[ "$include_realtime_service" == "true" ]]; then
    realtime_service_name="$(prompt "Realtime service repo name" "messenger")"
  fi
fi

include_agent_harness="$(prompt_yes_no "Include Claude/Cursor/Codex harness?" "y")"

if (( current_phase >= 3 )); then
  include_contract_harness="$(prompt_yes_no "Include cross-repo contract harness in this phase?" "y")"
else
  include_contract_harness="false"
fi

if (( current_phase >= 1 )); then
  include_preview_envs="$(prompt_yes_no "Include preview environments?" "y")"
else
  include_preview_envs="false"
fi

if (( current_phase >= 1 )); then
  if (( current_phase == 1 )); then
    demo_env_default="y"
  else
    demo_env_default="n"
  fi
  include_demo_env="$(prompt_yes_no "Include demo environment?" "$demo_env_default")"
else
  include_demo_env="false"
fi

if [[ "$include_mobile" == "true" ]]; then
  include_testflight="$(prompt_yes_no "Include TestFlight and OTA workflow scaffolding?" "y")"
else
  include_testflight="false"
fi

workspace_root_default="./${workspace_name}"
workspace_root="$(prompt "Workspace root to create or inspect" "$workspace_root_default")"
manifest_path="$(prompt "Manifest output path" "${workspace_root}/cto-bootstrap-manifest.json")"
create_scaffold="$(prompt_yes_no "Create local folder scaffold now?" "y")"
if [[ "$create_scaffold" == "true" ]]; then
  render_templates="$(prompt_yes_no "Render starter template files now?" "y")"
else
  render_templates="false"
fi

repo_names=()

if [[ "$include_infra" == "true" ]]; then
  append_unique "infrastructure"
fi

if [[ "$include_automations" == "true" ]]; then
  append_unique "automations"
fi

backend_repo_names=()
while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  backend_repo_names+=("$service")
  append_unique "$service"
done < <(csv_to_array "$backend_services")

if [[ "$include_platform_api" == "true" && -n "$platform_api_name" ]]; then
  backend_repo_names+=("$platform_api_name")
  append_unique "$platform_api_name"
fi

if [[ "$include_realtime_service" == "true" && -n "$realtime_service_name" ]]; then
  backend_repo_names+=("$realtime_service_name")
  append_unique "$realtime_service_name"
fi

web_app_names=()
while IFS= read -r app; do
  [[ -z "$app" ]] && continue
  web_app_names+=("$app")
done < <(csv_to_array "$portal_apps")

if [[ -n "${web_app_names[*]-}" && -n "$web_repo_name" ]]; then
  append_unique "$web_repo_name"
fi

mobile_repo_names=()
if [[ "$include_mobile" == "true" ]]; then
  while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    mobile_repo_names+=("$app")
    append_unique "$app"
  done < <(csv_to_array "$mobile_apps")
fi

if [[ "$include_internal_tools" == "true" ]]; then
  append_unique "internal-tools"
fi

repo_json=""
for repo in "${repo_names[@]}"; do
  [[ -n "$repo_json" ]] && repo_json+=", "
  repo_json+="\"$(json_escape "$repo")\""
done

repo_bullets="$(array_to_bullets "- No repos selected yet" "${repo_names[@]}")"
environments_inline="$(array_to_inline "none" $(csv_to_array "$environments"))"
if [[ -n "${backend_repo_names[*]-}" ]]; then
  backend_inline="$(array_to_inline "none" "${backend_repo_names[@]}")"
else
  backend_inline="none"
fi
if [[ -n "${web_app_names[*]-}" ]]; then
  web_inline="$(array_to_inline "none" "${web_app_names[@]}")"
else
  web_inline="none"
fi
if [[ -n "${mobile_repo_names[*]-}" ]]; then
  mobile_inline="$(array_to_inline "none" "${mobile_repo_names[@]}")"
else
  mobile_inline="none"
fi

if [[ "$create_scaffold" == "true" ]]; then
  mkdir -p "$workspace_root"
  mkdir -p "$workspace_root/work"
  for repo in "${repo_names[@]}"; do
    mkdir -p "$workspace_root/$repo"
  done
fi

manifest_dir="$(dirname "$manifest_path")"
mkdir -p "$manifest_dir"

cat > "$manifest_path" <<EOF
{
  "projectName": "$(json_escape "$project_name")",
  "projectSlug": "$(json_escape "$project_slug")",
  "workspaceName": "$(json_escape "$workspace_name")",
  "workspaceRoot": "$(json_escape "$workspace_root")",
  "awsRegion": "$(json_escape "$aws_region")",
  "platformProfile": {
    "cloud": "aws",
    "iac": "terraform",
    "compute": "ecs-fargate",
    "database": "postgresql",
    "backendRuntime": "bun",
    "backendFramework": "hono",
    "webFramework": "nextjs",
    "mobileFramework": "expo",
    "ci": "github-actions"
  },
  "architectureOverrides": [],
  "phase": {
    "id": ${current_phase},
    "name": "$(json_escape "$phase_slug")",
    "title": "$(json_escape "$phase_title_text")",
    "nextPhaseTitle": "$(json_escape "$next_phase_title_text")",
    "recommendation": "$(json_escape "$phase_recommendation_text")"
  },
  "branches": {
    "dev": "$(json_escape "$dev_branch")",
    "prod": "$(json_escape "$prod_branch")"
  },
  "environments": $(csv_to_json_array "$environments"),
  "domain": {
    "coreDomain": {
      "name": "$(json_escape "$core_domain_name")",
      "description": "$(json_escape "$core_domain_description")"
    },
    "supportingSubdomains": $(csv_to_json_array "$supporting_subdomains"),
    "boundedContexts": $(csv_to_json_array "$bounded_contexts"),
    "ubiquitousLanguage": $(csv_to_json_array "$ubiquitous_language")
  },
  "repos": [${repo_json}],
  "backendServices": $(csv_to_json_array "$backend_services"),
  "webApps": $(csv_to_json_array "$portal_apps"),
  "mobileApps": $(csv_to_json_array "$mobile_apps"),
  "features": {
    "infrastructureRepo": $(bool_string "$include_infra"),
    "automationsRepo": $(bool_string "$include_automations"),
    "internalToolsRepo": $(bool_string "$include_internal_tools"),
    "platformApiRepo": $(bool_string "$include_platform_api"),
    "realtimeServiceRepo": $(bool_string "$include_realtime_service"),
    "agentHarness": $(bool_string "$include_agent_harness"),
    "contractHarness": $(bool_string "$include_contract_harness"),
    "previewEnvironments": $(bool_string "$include_preview_envs"),
    "demoEnvironment": $(bool_string "$include_demo_env"),
    "mobileIncluded": $(bool_string "$include_mobile"),
    "testflightWorkflows": $(bool_string "$include_testflight"),
    "renderTemplates": $(bool_string "$render_templates")
  },
  "recommendedNextSteps": [
    "Confirm the selected phase and repo plan.",
    "Install the parent workspace handbook and agent harness files.",
    "Keep the default AWS, Terraform, and ECS profile unless a real constraint justifies override.",
    "Stand up the first shared deployed environment when moving beyond local MVP.",
    "Tighten CI/CD and operational scripts before the first production launch.",
    "Introduce cross-repo contracts only once multiple clients depend on shared APIs."
  ]
}
EOF

generated_files=()

# Build multi-line SERVICES_CONFIG arrays for ops scripts.
services_config_lines=""
log_services_config_lines=""
if [[ -n "${backend_repo_names[*]-}" ]]; then
  for repo in "${backend_repo_names[@]}"; do
    services_config_lines+="    \"${repo}:${repo}:${prod_branch}:prod:\"
"
    services_config_lines+="    \"dev-${repo}:${repo}:${dev_branch}:dev:dev-\"
"
    log_services_config_lines+="    \"${repo}:${repo}\"
"
    log_services_config_lines+="    \"dev-${repo}:dev-${repo}\"
"
  done
  # Strip trailing newline
  services_config_lines="${services_config_lines%$'\n'}"
  log_services_config_lines="${log_services_config_lines%$'\n'}"
else
  services_config_lines="    # TODO: add one line per ECS service. Format:"
  services_config_lines+=$'\n'"    #   \"ecs_service:repo_name:git_branch:env:ecr_tag_prefix\""
  log_services_config_lines="    # TODO: add one line per service. Format: \"service_name:stream_prefix\""
fi

# Build mobile APPS_CONFIG lines (user must fill in EAS project IDs and ASC app IDs).
mobile_apps_config_lines=""
if [[ "$include_mobile" == "true" && -n "${mobile_repo_names[*]-}" ]]; then
  for app in "${mobile_repo_names[@]}"; do
    app_slug="$(slugify "$app")"
    mobile_apps_config_lines+="    \"${app}:${app}:${expo_account_slug}-${app_slug}:com.example.${app_slug//-/}:TODO_EAS_PROJECT_ID:TODO_ASC_APP_ID\"
"
  done
  mobile_apps_config_lines="${mobile_apps_config_lines%$'\n'}"
else
  mobile_apps_config_lines="    # TODO: add one line per mobile app. See script header for format."
fi

supporting_subdomain_list=()
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  supporting_subdomain_list+=("$item")
done < <(csv_to_array "$supporting_subdomains")

bounded_context_list=()
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  bounded_context_list+=("$item")
done < <(csv_to_array "$bounded_contexts")

ubiquitous_language_list=()
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  ubiquitous_language_list+=("$item")
done < <(csv_to_array "$ubiquitous_language")

supporting_subdomain_bullets="$(array_to_bullets "- None identified yet." "${supporting_subdomain_list[@]}")"
bounded_context_bullets="$(array_to_bullets "- TBD — record bounded contexts as they emerge." "${bounded_context_list[@]}")"
ubiquitous_language_bullets="$(array_to_bullets "- TBD — seed glossary after first customer or domain-expert conversation." "${ubiquitous_language_list[@]}")"

if [[ -z "$core_domain_description" ]]; then
  core_domain_description_display="_Not set — fill in during the first domain conversation._"
else
  core_domain_description_display="$core_domain_description"
fi

export CTO_PROJECT_NAME="$project_name"
export CTO_PROJECT_SLUG="$project_slug"
export CTO_WORKSPACE_NAME="$workspace_name"
export CTO_AWS_REGION="$aws_region"
export CTO_CORE_DOMAIN_NAME="$core_domain_name"
export CTO_CORE_DOMAIN_DESCRIPTION="$core_domain_description_display"
export CTO_SUPPORTING_SUBDOMAIN_BULLETS="$supporting_subdomain_bullets"
export CTO_BOUNDED_CONTEXT_BULLETS="$bounded_context_bullets"
export CTO_UBIQUITOUS_LANGUAGE_BULLETS="$ubiquitous_language_bullets"
export CTO_DEV_BRANCH="$dev_branch"
export CTO_PROD_BRANCH="$prod_branch"
export CTO_PHASE_NAME="$phase_title_text"
export CTO_ENVIRONMENTS_INLINE="$environments_inline"
export CTO_BACKEND_SERVICES_INLINE="$backend_inline"
export CTO_WEB_APPS_INLINE="$web_inline"
export CTO_MOBILE_APPS_INLINE="$mobile_inline"
export CTO_REPO_BULLETS="$repo_bullets"
export CTO_GITHUB_ORG="$github_org"
export CTO_ECS_CLUSTER="$ecs_cluster"
export CTO_ECS_LOG_GROUP="$ecs_log_group"
export CTO_WAF_LOG_GROUP="$waf_log_group"
export CTO_VPC_FLOW_LOG_GROUP="$vpc_flow_log_group"
export CTO_ECR_NAMESPACE="$ecr_namespace"
export CTO_EXPO_ACCOUNT_SLUG="$expo_account_slug"
export CTO_SERVICES_CONFIG_LINES="$services_config_lines"
export CTO_LOG_SERVICES_CONFIG_LINES="$log_services_config_lines"
export CTO_MOBILE_APPS_CONFIG_LINES="$mobile_apps_config_lines"
export CTO_PROD_RDS_HOST="prod-${project_slug}-db.REPLACE-WITH-RDS-ENDPOINT"
export CTO_DEV_RDS_HOST="dev-${project_slug}-db.REPLACE-WITH-RDS-ENDPOINT"
export CTO_PROD_BASTION_NAME_TAG="${project_slug}-prod-bastion"
export CTO_DEV_BASTION_NAME_TAG="${project_slug}-dev-bastion"
export CTO_DB_USER="${project_slug//-/_}_admin"
export CTO_DB_NAME="${project_slug//-/_}"
export CTO_DB_SECRET_ID="${project_slug}/prod/database-url"
export CTO_DB_SECRET_ID_DEV="${project_slug}/dev/database-url"

if [[ "$render_templates" == "true" ]]; then
  render_template_file "${TEMPLATE_ROOT}/workspace/AGENTS.md.tpl" "${workspace_root}/AGENTS.md"
  render_template_file "${TEMPLATE_ROOT}/workspace/CLAUDE.md.tpl" "${workspace_root}/CLAUDE.md"
  render_template_file "${TEMPLATE_ROOT}/workspace/DOMAIN.md.tpl" "${workspace_root}/DOMAIN.md"

  if [[ "$include_agent_harness" == "true" ]]; then
    render_template_file "${TEMPLATE_ROOT}/workspace/.cursor/rules/repo-structure.mdc.tpl" "${workspace_root}/.cursor/rules/repo-structure.mdc"
    render_template_file "${TEMPLATE_ROOT}/workspace/.claude/settings.json.tpl" "${workspace_root}/.claude/settings.json"
    render_template_file "${TEMPLATE_ROOT}/workspace/.claude/hooks/pre-commit-lint.sh.tpl" "${workspace_root}/.claude/hooks/pre-commit-lint.sh"
    render_template_file "${TEMPLATE_ROOT}/workspace/.claude/hooks/terraform-safety.sh.tpl" "${workspace_root}/.claude/hooks/terraform-safety.sh"
    chmod +x "${workspace_root}/.claude/hooks/pre-commit-lint.sh" "${workspace_root}/.claude/hooks/terraform-safety.sh"

    # Agent rule skeletons — each ships with a self-prompt asking the agent to
    # interview the user the first time it touches that domain.
    for rule in _README backend-patterns database-migrations deployment testing contracts mobile-patterns infrastructure operations security; do
      render_template_file "${TEMPLATE_ROOT}/workspace/.claude/rules/${rule}.md.tpl" "${workspace_root}/.claude/rules/${rule}.md"
    done
  fi

  # Operational scripts become materially useful once there is deployed infrastructure.
  if [[ "$include_infra" == "true" || "$current_phase" -ge 1 ]]; then
    for script in check-deployment ecs-logs db-tunnel db-tunnel-dev terraform-pre-apply-guard prisma-check-sync waf-logs flow-logs check-mobile-builds; do
      render_template_file "${TEMPLATE_ROOT}/scripts/${script}.sh.tpl" "${workspace_root}/scripts/${script}.sh"
      chmod +x "${workspace_root}/scripts/${script}.sh"
    done
  fi

  if [[ "$include_infra" == "true" ]]; then
    render_template_file "${TEMPLATE_ROOT}/repo/infrastructure/terraform.yml.tpl" "${workspace_root}/infrastructure/.github/workflows/terraform.yml"
  fi

  if [[ "$include_automations" == "true" ]]; then
    render_template_file "${TEMPLATE_ROOT}/repo/automation/deploy.yml.tpl" "${workspace_root}/automations/.github/workflows/deploy.yml"
  fi

  if [[ -n "${backend_repo_names[*]-}" ]]; then
    for repo in "${backend_repo_names[@]}"; do
      export CTO_SERVICE_NAME="$repo"
      render_template_file "${TEMPLATE_ROOT}/repo/backend/deploy.yml.tpl" "${workspace_root}/${repo}/.github/workflows/deploy.yml"
    done
  fi

  if [[ -n "${web_app_names[*]-}" && -n "$web_repo_name" ]]; then
    render_template_file "${TEMPLATE_ROOT}/repo/web/ci.yml.tpl" "${workspace_root}/${web_repo_name}/.github/workflows/ci.yml"
  fi

  if [[ "$include_internal_tools" == "true" ]]; then
    render_template_file "${TEMPLATE_ROOT}/repo/web/ci.yml.tpl" "${workspace_root}/internal-tools/.github/workflows/ci.yml"
  fi

  if [[ "$include_mobile" == "true" && -n "${mobile_repo_names[*]-}" ]]; then
    for app in "${mobile_repo_names[@]}"; do
      app_slug="$(slugify "$app")"
      export CTO_APP_NAME="$app"
      export CTO_APP_SLUG="$app_slug"
      render_template_file "${TEMPLATE_ROOT}/repo/mobile/deploy.yml.tpl" "${workspace_root}/${app}/.github/workflows/deploy.yml"
      render_template_file "${TEMPLATE_ROOT}/repo/mobile/eas.json.tpl" "${workspace_root}/${app}/eas.json"
    done
  fi
fi

echo ""
echo "Manifest written to: $manifest_path"
echo ""
echo "Selected phase: $phase_title_text"
echo "$phase_recommendation_text"
echo ""
echo "Recommended repo set:"
for repo in "${repo_names[@]}"; do
  echo "  - $repo"
done

if [[ "$render_templates" == "true" ]]; then
  echo ""
  echo "Generated starter files:"
  for path in "${generated_files[@]}"; do
    echo "  - $path"
  done
fi

echo ""
echo "Immediate next steps:"
echo "  1. Open $(printf '%q' "$manifest_path") and confirm the repo plan."
echo "  2. Review the generated starter files and tighten each workflow for real secrets and deploy targets."
echo "  3. Use CTO-IN-A-BOX.md as the phased buildout guide while fleshing out the templates."
echo ""
