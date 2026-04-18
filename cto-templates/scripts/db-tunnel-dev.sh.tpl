#!/bin/bash
# =============================================================================
# DEV DATABASE TUNNEL - Opens local connection to dev databases via SSM bastion
# =============================================================================
# Same shape as db-tunnel.sh, but points at the dev RDS host (or dev database
# names if you share an instance). Be defensive: if dev and prod share an
# instance, only your dev IAM/credentials should grant access to dev databases.
#
# Usage:
#   ./db-tunnel-dev.sh           # Opens tunnel on local port 5434
#   ./db-tunnel-dev.sh 5435      # Opens tunnel on custom local port
# =============================================================================

set -e

# ==== CONFIGURATION (rendered by cto-bootstrap; tighten the TODOs once infra exists) ====
LOCAL_PORT="${1:-5434}"

# TODO: replace with your dev RDS endpoint (or your prod endpoint if you share one).
RDS_HOST="{{DEV_RDS_HOST}}"
RDS_PORT="5432"
REGION="{{AWS_REGION}}"

# TODO: replace with your dev bastion's Name tag.
BASTION_NAME_TAG="{{DEV_BASTION_NAME_TAG}}"

DB_USER="{{DB_USER}}"
DB_NAME_HINT="{{DB_NAME}}_dev"
DB_SECRET_ID="{{DB_SECRET_ID_DEV}}"
# =========================================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== Dev Database Tunnel via SSM ===${NC}"
echo ""
echo -e "${CYAN}Note: if dev and prod share an RDS instance, your IAM credentials"
echo -e "must restrict access to dev databases only.${NC}"
echo ""

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not installed${NC}"
    echo "Install with: brew install awscli"
    exit 1
fi

if ! command -v session-manager-plugin &> /dev/null; then
    echo -e "${RED}Error: AWS Session Manager plugin not installed${NC}"
    echo "Install with: brew install --cask session-manager-plugin"
    exit 1
fi

echo "Finding bastion instance ($BASTION_NAME_TAG)..."
BASTION_ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=${BASTION_NAME_TAG}" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ "$BASTION_ID" == "None" ] || [ -z "$BASTION_ID" ]; then
    echo -e "${RED}Error: Could not find running bastion instance with Name=$BASTION_NAME_TAG${NC}"
    exit 1
fi

echo -e "Bastion ID: ${GREEN}$BASTION_ID${NC}"
echo ""
echo -e "${YELLOW}Opening tunnel...${NC}"
echo -e "  Local:  127.0.0.1:${GREEN}$LOCAL_PORT${NC}"
echo -e "  Remote: $RDS_HOST:$RDS_PORT"
echo ""
echo -e "${YELLOW}Get the dev password:${NC}"
echo "  aws secretsmanager get-secret-value --secret-id \"$DB_SECRET_ID\" --region $REGION --query \"SecretString\" --output text | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p'"
echo ""
echo -e "${YELLOW}Connect with (use 127.0.0.1, not localhost):${NC}"
echo "  psql -h 127.0.0.1 -p $LOCAL_PORT -U $DB_USER -d $DB_NAME_HINT"
echo ""
echo -e "${YELLOW}For Prisma Studio:${NC}"
echo "  DATABASE_URL=\"postgresql://$DB_USER:PASSWORD@127.0.0.1:$LOCAL_PORT/$DB_NAME_HINT\" bunx prisma studio"
echo ""
echo -e "Press ${RED}Ctrl+C${NC} to close the tunnel"
echo ""

aws ssm start-session \
    --target "$BASTION_ID" \
    --region "$REGION" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"$RDS_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
