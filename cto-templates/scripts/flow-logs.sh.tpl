#!/bin/bash
# =============================================================================
# VPC FLOW LOG VIEWER
# =============================================================================
# Fetches CloudWatch logs for VPC flow logs in production.
# Flow logs capture metadata about every network connection in the VPC:
# source/dest IPs, ports, protocol, action (ACCEPT/REJECT), bytes.
#
# Usage: ./flow-logs.sh [OPTIONS]
#
# Quick examples:
#   ./flow-logs.sh                              # All traffic in last 15min
#   ./flow-logs.sh --since 1h --rejected        # Rejected traffic in last hour
#   ./flow-logs.sh --ip 10.0.1.45 --since 6h   # Traffic to/from an IP
#   ./flow-logs.sh --port 5432 --since 1h       # Database port traffic
#   ./flow-logs.sh --since 24h --summary        # Top talkers, rejected sources
#   ./flow-logs.sh --follow                     # Tail in real-time
#   ./flow-logs.sh --json                       # Structured output for parsing
# =============================================================================

set -e

# Configuration (rendered by cto-bootstrap)
LOG_GROUP="{{VPC_FLOW_LOG_GROUP}}"
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
    echo -e "${BOLD}VPC Flow Log Viewer${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC} ./flow-logs.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --since DURATION     How far back: 5m, 15m, 1h, 6h, 24h, 7d (default: 15m)"
    echo "  --filter PATTERN     CloudWatch text search pattern"
    echo "  --ip IP_ADDRESS      Filter by source or destination IP"
    echo "  --src-ip IP          Filter by source IP only"
    echo "  --dst-ip IP          Filter by destination IP only"
    echo "  --port PORT          Filter by source or destination port"
    echo "  --rejected           Show only REJECT actions"
    echo "  --accepted           Show only ACCEPT actions"
    echo "  --lines N            Max events to return (default: 200, max: 2000)"
    echo "  --follow, -f         Tail logs in real-time"
    echo "  --json, -j           Structured JSON output (best for AI parsing)"
    echo "  --summary            Top talkers, rejected sources, port breakdown"
    echo "  --raw                Show raw flow log lines"
    echo "  -h, --help           Show this help"
    echo ""
    echo -e "${BOLD}Flow Log Fields:${NC}"
    echo "  version account-id interface-id srcaddr dstaddr srcport dstport"
    echo "  protocol packets bytes start end action log-status"
    echo ""
    echo -e "${BOLD}Protocol Numbers:${NC}"
    echo "  6 = TCP    17 = UDP    1 = ICMP"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./flow-logs.sh --since 1h --rejected              # All rejected traffic"
    echo "  ./flow-logs.sh --ip 10.0.1.45 --since 6h          # Traffic to/from IP"
    echo "  ./flow-logs.sh --port 5432 --since 1h              # Postgres traffic"
    echo "  ./flow-logs.sh --port 6379 --since 1h              # Redis traffic"
    echo "  ./flow-logs.sh --src-ip 10.0.1.45 --port 443       # HTTPS from specific IP"
    echo "  ./flow-logs.sh --since 24h --summary               # Traffic summary"
    echo "  ./flow-logs.sh --since 1h --rejected --summary     # Rejected traffic summary"
    echo "  ./flow-logs.sh --follow --rejected                 # Tail rejected traffic"
    echo ""
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

SINCE="$DEFAULT_SINCE"
FILTER=""
IP_FILTER=""
SRC_IP_FILTER=""
DST_IP_FILTER=""
PORT_FILTER=""
ACTION_FILTER=""
LINES=$DEFAULT_LINES
FOLLOW=false
JSON_OUTPUT=false
SUMMARY=false
RAW=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --since)      SINCE="$2"; shift 2 ;;
        --filter)     FILTER="$2"; shift 2 ;;
        --ip)         IP_FILTER="$2"; shift 2 ;;
        --src-ip)     SRC_IP_FILTER="$2"; shift 2 ;;
        --dst-ip)     DST_IP_FILTER="$2"; shift 2 ;;
        --port)       PORT_FILTER="$2"; shift 2 ;;
        --rejected)   ACTION_FILTER="REJECT"; shift ;;
        --accepted)   ACTION_FILTER="ACCEPT"; shift ;;
        --lines)      LINES="$2"; shift 2 ;;
        --follow|-f)  FOLLOW=true; shift ;;
        --json|-j)    JSON_OUTPUT=true; shift ;;
        --summary)    SUMMARY=true; shift ;;
        --raw)        RAW=true; shift ;;
        -h|--help)    show_help; exit 0 ;;
        *)            echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
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
# VPC flow log format (space-delimited, one record per line):
#   version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
#
# CloudWatch filter pattern syntax for space-delimited logs:
#   [version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action, log_status]

build_filter() {
    local parts=()

    if [[ -n "$FILTER" ]]; then
        parts+=("\"$FILTER\"")
    fi

    if [[ -n "$IP_FILTER" ]]; then
        # Match IP in either srcaddr or dstaddr — use text match
        parts+=("\"$IP_FILTER\"")
    fi

    if [[ -n "$SRC_IP_FILTER" ]]; then
        parts+=("\"$SRC_IP_FILTER\"")
    fi

    if [[ -n "$DST_IP_FILTER" ]]; then
        parts+=("\"$DST_IP_FILTER\"")
    fi

    if [[ -n "$PORT_FILTER" ]]; then
        parts+=("\"$PORT_FILTER\"")
    fi

    if [[ -n "$ACTION_FILTER" ]]; then
        parts+=("\"$ACTION_FILTER\"")
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
# PROTOCOL NAME LOOKUP
# =============================================================================

protocol_name() {
    python3 -c "
proto_map = {'6': 'TCP', '17': 'UDP', '1': 'ICMP', '2': 'IGMP', '47': 'GRE', '50': 'ESP', '51': 'AH', '58': 'ICMPv6', '-': '-'}
print(proto_map.get('$1', '$1'))
"
}

# =============================================================================
# CHECK LOG GROUP EXISTS
# =============================================================================

check_log_group() {
    if ! aws logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP" \
        --region "$REGION" \
        --query "logGroups[?logGroupName=='$LOG_GROUP'].logGroupName" \
        --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        echo -e "${YELLOW}VPC flow log group not found: $LOG_GROUP${NC}"
        echo -e "${GRAY}Flow logs may not be deployed yet. Run 'terraform apply' in infrastructure/terraform/shared/prod/ first.${NC}"
        exit 0
    fi
}

check_log_group

# =============================================================================
# FOLLOW MODE
# =============================================================================

if [[ "$FOLLOW" == "true" ]]; then
    echo -e "${CYAN}Tailing VPC flow logs (Ctrl+C to stop)...${NC}"
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
        # Flow log lines: version account-id eni srcaddr dstaddr srcport dstport proto packets bytes start end action log-status
        echo "$line" | python3 -c "
import sys
proto_map = {'6': 'TCP', '17': 'UDP', '1': 'ICMP', '-': '-'}
for raw in sys.stdin:
    raw = raw.strip()
    # aws logs tail prepends a timestamp — find the flow log fields
    parts = raw.split()
    # Flow log has 14 fields; find them in the line
    # Try parsing from the end backwards or look for the pattern
    if len(parts) < 14:
        print(raw)
        continue
    # The flow log fields start after any prefix aws logs tail adds
    # Try last 14 fields
    fl = parts[-14:]
    try:
        ver, acct, eni, src, dst, sport, dport, proto, pkts, bts, start, end, action, status = fl
        proto_name = proto_map.get(proto, proto)
        if action == 'REJECT':
            color = '\033[0;31m'
        else:
            color = '\033[0;32m'
        print(f'{color}{action}\033[0m {src}:{sport} → {dst}:{dport} {proto_name} {pkts}pkts {bts}B \033[0;90m{eni}\033[0m')
    except:
        print(raw)
" 2>/dev/null
    done
    exit 0
fi

# =============================================================================
# SUMMARY MODE (uses CloudWatch Logs Insights for aggregation)
# =============================================================================

if [[ "$SUMMARY" == "true" ]]; then
    echo -e "${BOLD}VPC Flow Log Summary (last $SINCE)${NC}"
    echo ""

    # Use CloudWatch Logs Insights for efficient server-side aggregation
    END_TIME=$(( $(date +%s) * 1000 ))

    # Build the Insights query based on filters
    INSIGHTS_FILTER=""
    if [[ -n "$ACTION_FILTER" ]]; then
        INSIGHTS_FILTER="| filter action = \"$ACTION_FILTER\""
    fi
    if [[ -n "$IP_FILTER" ]]; then
        INSIGHTS_FILTER="$INSIGHTS_FILTER | filter srcAddr = \"$IP_FILTER\" or dstAddr = \"$IP_FILTER\""
    fi
    if [[ -n "$SRC_IP_FILTER" ]]; then
        INSIGHTS_FILTER="$INSIGHTS_FILTER | filter srcAddr = \"$SRC_IP_FILTER\""
    fi
    if [[ -n "$DST_IP_FILTER" ]]; then
        INSIGHTS_FILTER="$INSIGHTS_FILTER | filter dstAddr = \"$DST_IP_FILTER\""
    fi
    if [[ -n "$PORT_FILTER" ]]; then
        INSIGHTS_FILTER="$INSIGHTS_FILTER | filter srcPort = \"$PORT_FILTER\" or dstPort = \"$PORT_FILTER\""
    fi

    # Query 1: Overall stats
    QUERY_ID=$(aws logs start-query \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --query-string "parse @message \"* * * * * * * * * * * * * *\" as version, accountId, interfaceId, srcAddr, dstAddr, srcPort, dstPort, protocol, packets, bytes, startTime, endTime, action, logStatus $INSIGHTS_FILTER | stats count(*) as total, sum(bytes) as totalBytes by action" \
        --region "$REGION" \
        --output text --query 'queryId' 2>/dev/null)

    # Query 2: Top source IPs
    QUERY_ID_SRC=$(aws logs start-query \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --query-string "parse @message \"* * * * * * * * * * * * * *\" as version, accountId, interfaceId, srcAddr, dstAddr, srcPort, dstPort, protocol, packets, bytes, startTime, endTime, action, logStatus $INSIGHTS_FILTER | stats count(*) as flows, sum(bytes) as totalBytes by srcAddr | sort flows desc | limit 10" \
        --region "$REGION" \
        --output text --query 'queryId' 2>/dev/null)

    # Query 3: Top destination ports
    QUERY_ID_PORT=$(aws logs start-query \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --query-string "parse @message \"* * * * * * * * * * * * * *\" as version, accountId, interfaceId, srcAddr, dstAddr, srcPort, dstPort, protocol, packets, bytes, startTime, endTime, action, logStatus $INSIGHTS_FILTER | stats count(*) as flows, sum(bytes) as totalBytes by dstPort, protocol | sort flows desc | limit 15" \
        --region "$REGION" \
        --output text --query 'queryId' 2>/dev/null)

    # Query 4: Top rejected sources (always useful)
    QUERY_ID_REJ=$(aws logs start-query \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --query-string "parse @message \"* * * * * * * * * * * * * *\" as version, accountId, interfaceId, srcAddr, dstAddr, srcPort, dstPort, protocol, packets, bytes, startTime, endTime, action, logStatus | filter action = \"REJECT\" | stats count(*) as rejected by srcAddr, dstPort | sort rejected desc | limit 10" \
        --region "$REGION" \
        --output text --query 'queryId' 2>/dev/null)

    # Wait for queries to complete
    sleep 3

    wait_for_query() {
        local qid="$1"
        local max_wait=30
        local waited=0
        while [[ $waited -lt $max_wait ]]; do
            local status
            status=$(aws logs get-query-results --query-id "$qid" --region "$REGION" --query 'status' --output text 2>/dev/null)
            if [[ "$status" == "Complete" ]]; then
                return 0
            fi
            sleep 1
            waited=$((waited + 1))
        done
        return 1
    }

    wait_for_query "$QUERY_ID"

    # Display results
    echo -e "  ${WHITE}Traffic by Action:${NC}"
    aws logs get-query-results --query-id "$QUERY_ID" --region "$REGION" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('results', []):
    fields = {f['field']: f['value'] for f in row}
    action = fields.get('action', '?')
    total = fields.get('total', '0')
    total_bytes = int(fields.get('totalBytes', '0'))
    if total_bytes > 1073741824:
        size = f'{total_bytes/1073741824:.1f} GB'
    elif total_bytes > 1048576:
        size = f'{total_bytes/1048576:.1f} MB'
    elif total_bytes > 1024:
        size = f'{total_bytes/1024:.1f} KB'
    else:
        size = f'{total_bytes} B'
    color = '\033[0;31m' if action == 'REJECT' else '\033[0;32m'
    print(f'    {color}{action}\033[0m  {total:>8} flows  {size:>10}')
"
    echo ""

    wait_for_query "$QUERY_ID_SRC"

    echo -e "  ${CYAN}Top Source IPs:${NC}"
    aws logs get-query-results --query-id "$QUERY_ID_SRC" --region "$REGION" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('results', []):
    fields = {f['field']: f['value'] for f in row}
    src = fields.get('srcAddr', '?')
    flows = fields.get('flows', '0')
    total_bytes = int(fields.get('totalBytes', '0'))
    if total_bytes > 1073741824:
        size = f'{total_bytes/1073741824:.1f} GB'
    elif total_bytes > 1048576:
        size = f'{total_bytes/1048576:.1f} MB'
    elif total_bytes > 1024:
        size = f'{total_bytes/1024:.1f} KB'
    else:
        size = f'{total_bytes} B'
    print(f'    {flows:>8} flows  {size:>10}  {src}')
"
    echo ""

    wait_for_query "$QUERY_ID_PORT"

    echo -e "  ${MAGENTA}Top Destination Ports:${NC}"
    aws logs get-query-results --query-id "$QUERY_ID_PORT" --region "$REGION" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
proto_map = {'6': 'TCP', '17': 'UDP', '1': 'ICMP', '-': '-'}
well_known = {'443': 'HTTPS', '80': 'HTTP', '5432': 'Postgres', '6379': 'Redis', '53': 'DNS', '22': 'SSH', '3000': 'App', '8080': 'Alt-HTTP'}
for row in data.get('results', []):
    fields = {f['field']: f['value'] for f in row}
    port = fields.get('dstPort', '?')
    proto = proto_map.get(fields.get('protocol', '?'), fields.get('protocol', '?'))
    flows = fields.get('flows', '0')
    total_bytes = int(fields.get('totalBytes', '0'))
    if total_bytes > 1073741824:
        size = f'{total_bytes/1073741824:.1f} GB'
    elif total_bytes > 1048576:
        size = f'{total_bytes/1048576:.1f} MB'
    elif total_bytes > 1024:
        size = f'{total_bytes/1024:.1f} KB'
    else:
        size = f'{total_bytes} B'
    label = well_known.get(port, '')
    if label:
        label = f' ({label})'
    print(f'    {flows:>8} flows  {size:>10}  :{port}/{proto}{label}')
"
    echo ""

    wait_for_query "$QUERY_ID_REJ"

    echo -e "  ${RED}Top Rejected (source → dest port):${NC}"
    aws logs get-query-results --query-id "$QUERY_ID_REJ" --region "$REGION" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
if not results:
    print('    No rejected traffic found.')
else:
    for row in results:
        fields = {f['field']: f['value'] for f in row}
        src = fields.get('srcAddr', '?')
        port = fields.get('dstPort', '?')
        rejected = fields.get('rejected', '0')
        print(f'    {rejected:>8} rejects  {src} → :{port}')
"
    echo ""

    # Print stats line
    aws logs get-query-results --query-id "$QUERY_ID" --region "$REGION" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
stats = data.get('statistics', {})
scanned = stats.get('bytesScanned', 0)
records = stats.get('recordsScanned', 0)
if scanned > 1048576:
    size = f'{scanned/1048576:.1f} MB'
elif scanned > 1024:
    size = f'{scanned/1024:.1f} KB'
else:
    size = f'{scanned} B'
print(f'\033[0;90mScanned {records:,.0f} records ({size})\033[0m')
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
    echo -e "${YELLOW}No flow log group found. Flow logs may not be deployed yet.${NC}"
    echo -e "${GRAY}Expected log group: $LOG_GROUP${NC}"
    exit 0
fi

# JSON output mode
if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$EVENTS" | python3 -c "
import sys, json

proto_map = {'6': 'TCP', '17': 'UDP', '1': 'ICMP', '-': '-'}
data = json.load(sys.stdin)
events = data.get('events', [])
results = []

for e in events:
    msg = e.get('message', '').strip()
    parts = msg.split()
    if len(parts) < 14:
        continue
    try:
        ver, acct, eni, src, dst, sport, dport, proto, pkts, bts, start, end, action, status = parts[:14]
        results.append({
            'timestamp': int(start) * 1000 if start != '-' else e.get('timestamp'),
            'interface': eni,
            'srcAddr': src,
            'dstAddr': dst,
            'srcPort': int(sport) if sport != '-' else None,
            'dstPort': int(dport) if dport != '-' else None,
            'protocol': proto_map.get(proto, proto),
            'packets': int(pkts) if pkts != '-' else 0,
            'bytes': int(bts) if bts != '-' else 0,
            'action': action,
        })
    except:
        pass

# Apply post-filters for src/dst specificity that text match can't do
src_ip = '$SRC_IP_FILTER'
dst_ip = '$DST_IP_FILTER'
ip_filter = '$IP_FILTER'
port_filter = '$PORT_FILTER'

if src_ip:
    results = [r for r in results if r['srcAddr'] == src_ip]
if dst_ip:
    results = [r for r in results if r['dstAddr'] == dst_ip]
if port_filter:
    p = int(port_filter)
    results = [r for r in results if r['srcPort'] == p or r['dstPort'] == p]

print(json.dumps({'flow_logs': results[:$LINES], 'count': len(results), 'truncated': len(results) > $LINES}, indent=2))
" 2>/dev/null
    exit 0
fi

# Raw mode
if [[ "$RAW" == "true" ]]; then
    echo "$EVENTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
events = data.get('events', [])
if not events:
    print('No flow log events found.')
else:
    for e in events[:$LINES]:
        print(e.get('message', '').strip())
" 2>/dev/null
    exit 0
fi

# Human-friendly output (default)
echo "$EVENTS" | python3 -c "
import sys, json
from datetime import datetime

proto_map = {'6': 'TCP', '17': 'UDP', '1': 'ICMP', '2': 'IGMP', '-': '-'}
well_known = {'443': 'HTTPS', '80': 'HTTP', '5432': 'PG', '6379': 'Redis', '53': 'DNS', '22': 'SSH', '3000': 'App'}

data = json.load(sys.stdin)
events = data.get('events', [])

if not events:
    print('\033[0;32mNo flow log events in the last period.\033[0m')
    sys.exit(0)

# Parse and optionally post-filter
parsed = []
for e in events:
    msg = e.get('message', '').strip()
    parts = msg.split()
    if len(parts) < 14:
        continue
    try:
        ver, acct, eni, src, dst, sport, dport, proto, pkts, bts, start, end, action, status = parts[:14]
        parsed.append({
            'eni': eni, 'src': src, 'dst': dst, 'sport': sport, 'dport': dport,
            'proto': proto, 'pkts': pkts, 'bts': bts, 'start': start, 'end': end,
            'action': action,
        })
    except:
        pass

# Post-filter for specificity
src_ip = '$SRC_IP_FILTER'
dst_ip = '$DST_IP_FILTER'
ip_filter = '$IP_FILTER'
port_filter = '$PORT_FILTER'

if src_ip:
    parsed = [r for r in parsed if r['src'] == src_ip]
if dst_ip:
    parsed = [r for r in parsed if r['dst'] == dst_ip]
if port_filter:
    parsed = [r for r in parsed if r['sport'] == port_filter or r['dport'] == port_filter]

if not parsed:
    print('\033[0;32mNo matching flow log events.\033[0m')
    sys.exit(0)

showing = parsed[:$LINES]
print(f'\033[1;37m{len(parsed)} flow(s) found (showing {len(showing)}):\033[0m')
print()

for r in showing:
    action = r['action']
    if action == 'REJECT':
        color = '\033[0;31m'
    else:
        color = '\033[0;32m'

    proto_name = proto_map.get(r['proto'], r['proto'])
    start_ts = r['start']
    if start_ts != '-':
        time_str = datetime.fromtimestamp(int(start_ts)).strftime('%Y-%m-%d %H:%M:%S')
    else:
        time_str = '?'

    bts = int(r['bts']) if r['bts'] != '-' else 0
    if bts > 1048576:
        size = f'{bts/1048576:.1f}MB'
    elif bts > 1024:
        size = f'{bts/1024:.1f}KB'
    else:
        size = f'{bts}B'

    dport_label = well_known.get(r['dport'], '')
    if dport_label:
        dport_label = f' ({dport_label})'

    print(f'  {color}{action:6}\033[0m {time_str}  {r[\"src\"]}:{r[\"sport\"]} → {r[\"dst\"]}:{r[\"dport\"]}{dport_label}  {proto_name} {r[\"pkts\"]}pkts {size}  \033[0;90m{r[\"eni\"]}\033[0m')
" 2>/dev/null
