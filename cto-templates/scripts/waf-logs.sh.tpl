#!/bin/bash
# =============================================================================
# WAF LOG VIEWER
# =============================================================================
# Fetches CloudWatch logs for the WAF Web ACL attached to the prod ALB.
# Only blocked requests are logged (configured in Terraform).
#
# Usage: ./waf-logs.sh [OPTIONS]
#
# Quick examples:
#   ./waf-logs.sh                          # Blocked requests in last 15min
#   ./waf-logs.sh --since 1h              # Last hour
#   ./waf-logs.sh --since 24h --summary   # Summary of which rules are firing
#   ./waf-logs.sh --filter "/user/"       # Blocks targeting user-api routes
#   ./waf-logs.sh --follow                # Tail blocked requests in real-time
#   ./waf-logs.sh --json                  # Structured output for AI parsing
# =============================================================================

set -e

# Configuration (rendered by cto-bootstrap)
LOG_GROUP="{{WAF_LOG_GROUP}}"
REGION="{{AWS_REGION}}"

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
# HELP
# =============================================================================

show_help() {
    echo -e "${BOLD}WAF Log Viewer${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC} ./waf-logs.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --since DURATION     How far back: 5m, 15m, 1h, 6h, 24h, 7d (default: 15m)"
    echo "  --filter PATTERN     CloudWatch text search pattern"
    echo "  --rule RULE_NAME     Filter by WAF rule name (e.g., RateLimitRule, AWSManagedRulesCommonRuleSet)"
    echo "  --uri URI_PATTERN    Filter by request URI path"
    echo "  --ip IP_ADDRESS      Filter by source IP"
    echo "  --lines N            Max events to return (default: 200, max: 2000)"
    echo "  --follow, -f         Tail logs in real-time"
    echo "  --json, -j           Structured JSON output (best for AI parsing)"
    echo "  --summary            Show rule-level summary of blocked requests"
    echo "  --raw                Show raw WAF log JSON (verbose)"
    echo "  -h, --help           Show this help"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./waf-logs.sh --since 1h                      # All blocks in last hour"
    echo "  ./waf-logs.sh --since 6h --summary             # Which rules fired most"
    echo "  ./waf-logs.sh --rule RateLimitRule --since 1h  # Rate-limited IPs"
    echo "  ./waf-logs.sh --uri '/user/' --since 1h        # Blocks on user-api routes"
    echo "  ./waf-logs.sh --ip 1.2.3.4                     # Blocks from specific IP"
    echo "  ./waf-logs.sh --follow                         # Real-time blocked requests"
    echo ""
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

SINCE="$DEFAULT_SINCE"
FILTER=""
RULE_FILTER=""
URI_FILTER=""
IP_FILTER=""
LINES=$DEFAULT_LINES
FOLLOW=false
JSON_OUTPUT=false
SUMMARY=false
RAW=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --since)     SINCE="$2"; shift 2 ;;
        --filter)    FILTER="$2"; shift 2 ;;
        --rule)      RULE_FILTER="$2"; shift 2 ;;
        --uri)       URI_FILTER="$2"; shift 2 ;;
        --ip)        IP_FILTER="$2"; shift 2 ;;
        --lines)     LINES="$2"; shift 2 ;;
        --follow|-f) FOLLOW=true; shift ;;
        --json|-j)   JSON_OUTPUT=true; shift ;;
        --summary)   SUMMARY=true; shift ;;
        --raw)       RAW=true; shift ;;
        -h|--help)   show_help; exit 0 ;;
        *)           echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
done

# Cap lines
if [[ $LINES -gt $MAX_LINES ]]; then
    LINES=$MAX_LINES
fi

# =============================================================================
# TIME CALCULATION
# =============================================================================

parse_since() {
    local since="$1"
    local now
    now=$(date +%s)

    case "$since" in
        *m) echo $(( (now - ${since%m} * 60) * 1000 )) ;;
        *h) echo $(( (now - ${since%h} * 3600) * 1000 )) ;;
        *d) echo $(( (now - ${since%d} * 86400) * 1000 )) ;;
        *)  echo -e "${RED}Invalid duration: $since (use Nm, Nh, or Nd)${NC}" >&2; exit 1 ;;
    esac
}

START_TIME=$(parse_since "$SINCE")

# =============================================================================
# BUILD FILTER PATTERN
# =============================================================================

build_filter() {
    local parts=()

    if [[ -n "$FILTER" ]]; then
        parts+=("\"$FILTER\"")
    fi
    if [[ -n "$RULE_FILTER" ]]; then
        parts+=("\"$RULE_FILTER\"")
    fi
    if [[ -n "$URI_FILTER" ]]; then
        parts+=("\"$URI_FILTER\"")
    fi
    if [[ -n "$IP_FILTER" ]]; then
        parts+=("\"$IP_FILTER\"")
    fi

    if [[ ${#parts[@]} -eq 0 ]]; then
        echo ""
    else
        local joined=""
        for p in "${parts[@]}"; do
            if [[ -n "$joined" ]]; then
                joined="$joined $p"
            else
                joined="$p"
            fi
        done
        echo "$joined"
    fi
}

FILTER_PATTERN=$(build_filter)

# =============================================================================
# FOLLOW MODE
# =============================================================================

if [[ "$FOLLOW" == "true" ]]; then
    echo -e "${CYAN}Tailing WAF blocked requests (Ctrl+C to stop)...${NC}"
    echo ""

    TAIL_CMD=(aws logs tail "$LOG_GROUP"
        --region "$REGION"
        --follow
        --format short
    )

    if [[ -n "$FILTER_PATTERN" ]]; then
        TAIL_CMD+=(--filter-pattern "$FILTER_PATTERN")
    fi

    "${TAIL_CMD[@]}" 2>/dev/null | while IFS= read -r line; do
        # Try to parse as JSON and format nicely
        if echo "$line" | python3 -c "
import sys, json
try:
    # aws logs tail prepends a timestamp prefix — strip it
    raw = sys.stdin.read().strip()
    # Find the JSON part (starts with {)
    idx = raw.find('{')
    if idx == -1:
        print(raw)
        sys.exit(0)
    data = json.loads(raw[idx:])
    action = data.get('action', '?')
    rule = 'unknown'
    for r in data.get('ruleGroupList', []):
        for er in r.get('excludedRules', []):
            pass
        for tr in r.get('terminatingRule', {}) or []:
            pass
    term = data.get('terminatingRule', {})
    if term:
        rule = term.get('ruleId', 'unknown')
    uri = data.get('httpRequest', {}).get('uri', '?')
    ip = data.get('httpRequest', {}).get('clientIp', '?')
    host = '?'
    for h in data.get('httpRequest', {}).get('headers', []):
        if h.get('name', '').lower() == 'host':
            host = h.get('value', '?')
            break
    method = data.get('httpRequest', {}).get('httpMethod', '?')
    ts = data.get('timestamp', 0)
    from datetime import datetime
    time_str = datetime.fromtimestamp(ts/1000).strftime('%H:%M:%S') if ts else '?'
    print(f'\033[0;31mBLOCKED\033[0m {time_str} \033[1;37m{method} {host}{uri}\033[0m from \033[0;36m{ip}\033[0m — rule: \033[0;33m{rule}\033[0m')
except:
    print(raw)
" 2>/dev/null; then
            :
        fi
    done
    exit 0
fi

# =============================================================================
# SUMMARY MODE
# =============================================================================

if [[ "$SUMMARY" == "true" ]]; then
    echo -e "${BOLD}WAF Block Summary (last $SINCE)${NC}"
    echo ""

    QUERY_CMD=(aws logs filter-log-events
        --log-group-name "$LOG_GROUP"
        --region "$REGION"
        --start-time "$START_TIME"
        --no-paginate
    )

    if [[ -n "$FILTER_PATTERN" ]]; then
        QUERY_CMD+=(--filter-pattern "$FILTER_PATTERN")
    fi

    EVENTS=$("${QUERY_CMD[@]}" 2>/dev/null || echo '{"events":[]}')

    echo "$EVENTS" | python3 -c "
import sys, json
from collections import Counter
from datetime import datetime

data = json.load(sys.stdin)
events = data.get('events', [])

if not events:
    print('  No blocked requests found.')
    sys.exit(0)

rules = Counter()
ips = Counter()
uris = Counter()
hosts = Counter()

for e in events:
    try:
        log = json.loads(e['message'])
        # terminatingRuleId is top-level for managed rule groups
        rule_id = log.get('terminatingRuleId', 'unknown')
        # Try to get the specific sub-rule from ruleGroupList
        for rg in log.get('ruleGroupList', []):
            tr = rg.get('terminatingRule')
            if tr and tr.get('ruleId'):
                rule_id = rule_id + '/' + tr.get('ruleId', '')
                break
        rules[rule_id] += 1

        req = log.get('httpRequest', {})
        ips[req.get('clientIp', '?')] += 1
        uris[req.get('uri', '?')] += 1
        for h in req.get('headers', []):
            if h.get('name', '').lower() == 'host':
                hosts[h.get('value', '?')] += 1
                break
    except:
        pass

print(f'  \033[1;37mTotal blocked requests:\033[0m {len(events)}')
print()

print(f'  \033[1;33mBy Rule:\033[0m')
for rule, count in rules.most_common(10):
    print(f'    {count:>5}  {rule}')
print()

print(f'  \033[0;36mBy Source IP:\033[0m')
for ip, count in ips.most_common(10):
    print(f'    {count:>5}  {ip}')
print()

print(f'  \033[1;37mBy Host:\033[0m')
for host, count in hosts.most_common(10):
    print(f'    {count:>5}  {host}')
print()

print(f'  \033[0;35mBy URI (top 10):\033[0m')
for uri, count in uris.most_common(10):
    print(f'    {count:>5}  {uri}')
" 2>/dev/null
    exit 0
fi

# =============================================================================
# FETCH MODE (default)
# =============================================================================

QUERY_CMD=(aws logs filter-log-events
    --log-group-name "$LOG_GROUP"
    --region "$REGION"
    --start-time "$START_TIME"
    --no-paginate
)

if [[ -n "$FILTER_PATTERN" ]]; then
    QUERY_CMD+=(--filter-pattern "$FILTER_PATTERN")
fi

EVENTS=$("${QUERY_CMD[@]}" 2>/dev/null || echo '{"events":[]}')

if [[ -z "$EVENTS" ]]; then
    echo -e "${YELLOW}No WAF log group found. WAF may not be deployed yet.${NC}"
    echo -e "${GRAY}Expected log group: $LOG_GROUP${NC}"
    exit 0
fi

# JSON output mode
if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$EVENTS" | python3 -c "
import sys, json

data = json.load(sys.stdin)
events = data.get('events', [])
results = []

for e in events:
    try:
        log = json.loads(e['message'])
        rule_id = log.get('terminatingRuleId', 'unknown')
        rule_type = log.get('terminatingRuleType', None)
        for rg in log.get('ruleGroupList', []):
            tr = rg.get('terminatingRule')
            if tr and tr.get('ruleId'):
                rule_id = rule_id + '/' + tr.get('ruleId', '')
                break
        req = log.get('httpRequest', {})
        host = '?'
        for h in req.get('headers', []):
            if h.get('name', '').lower() == 'host':
                host = h.get('value', '?')
                break
        results.append({
            'timestamp': log.get('timestamp'),
            'action': log.get('action'),
            'rule': rule_id,
            'ruleType': rule_type,
            'ip': req.get('clientIp'),
            'method': req.get('httpMethod'),
            'host': host,
            'uri': req.get('uri'),
            'country': req.get('country'),
        })
    except:
        pass

print(json.dumps({'blocked_requests': results, 'count': len(results)}, indent=2))
" 2>/dev/null
    exit 0
fi

# Raw mode
if [[ "$RAW" == "true" ]]; then
    echo "$EVENTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data.get('events', []):
    try:
        log = json.loads(e['message'])
        print(json.dumps(log, indent=2))
        print('---')
    except:
        print(e.get('message', ''))
" 2>/dev/null
    exit 0
fi

# Human-friendly output (default)
echo "$EVENTS" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
events = data.get('events', [])

if not events:
    print('\033[0;32mNo blocked requests in the last period. All clear.\033[0m')
    sys.exit(0)

print(f'\033[1;37m{len(events)} blocked request(s):\033[0m')
print()

for e in events:
    try:
        log = json.loads(e['message'])
        rule = log.get('terminatingRuleId', '?')
        for rg in log.get('ruleGroupList', []):
            tr = rg.get('terminatingRule')
            if tr and tr.get('ruleId'):
                rule = rule + '/' + tr.get('ruleId', '')
                break
        req = log.get('httpRequest', {})
        ip = req.get('clientIp', '?')
        method = req.get('httpMethod', '?')
        uri = req.get('uri', '?')
        country = req.get('country', '?')
        host = '?'
        for h in req.get('headers', []):
            if h.get('name', '').lower() == 'host':
                host = h.get('value', '?')
                break

        ts = log.get('timestamp', 0)
        time_str = datetime.fromtimestamp(ts/1000).strftime('%Y-%m-%d %H:%M:%S') if ts else '?'

        print(f'  \033[0;31mBLOCKED\033[0m {time_str}')
        print(f'    \033[1;37m{method} {host}{uri}\033[0m')
        print(f'    IP: \033[0;36m{ip}\033[0m ({country})  Rule: \033[0;33m{rule}\033[0m')
        print()
    except:
        print(f'  {e.get(\"message\", \"?\")[:200]}')
        print()
" 2>/dev/null
