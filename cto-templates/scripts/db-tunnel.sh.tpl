#!/bin/bash
# =============================================================================
# DATABASE TUNNEL - Opens local connection to prod RDS via SSM bastion
# =============================================================================
# Creates a port-forwarding tunnel through the bastion host so you can connect
# to RDS from your local machine without exposing it to the public internet.
#
# Usage:
#   ./db-tunnel.sh           # Opens tunnel on local port 5434
#   ./db-tunnel.sh 5435      # Opens tunnel on custom local port
#
# Then connect with:
#   psql -h localhost -p 5434 -U {{DB_USER}} -d {{DB_NAME}}
#
# To get the password from AWS Secrets Manager:
#   aws secretsmanager get-secret-value \
#     --secret-id "{{DB_SECRET_ID}}" \
#     --region {{AWS_REGION}} \
#     --query "SecretString" --output text \
#     | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p'
# =============================================================================

set -e

# ==== CONFIGURATION (rendered by cto-bootstrap; tighten the TODOs once infra exists) ====
LOCAL_PORT="${1:-5434}"

# TODO: replace with your prod RDS endpoint once Terraform creates it.
RDS_HOST="{{PROD_RDS_HOST}}"
RDS_PORT="5432"
REGION="{{AWS_REGION}}"

# TODO: replace with your bastion's Name tag (e.g. "{{PROJECT_SLUG}}-prod-bastion").
BASTION_NAME_TAG="{{PROD_BASTION_NAME_TAG}}"

# TODO: replace with the master username configured in your RDS module.
DB_USER="{{DB_USER}}"
DB_NAME="{{DB_NAME}}"
DB_SECRET_ID="{{DB_SECRET_ID}}"
# =========================================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== RDS Tunnel via SSM (prod) ===${NC}"
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
echo -e "  Local:  localhost:${GREEN}$LOCAL_PORT${NC}"
echo -e "  Remote: $RDS_HOST:$RDS_PORT"
echo ""
echo -e "${YELLOW}Get the password:${NC}"
echo "  aws secretsmanager get-secret-value --secret-id \"$DB_SECRET_ID\" --region $REGION --query \"SecretString\" --output text | sed -n 's|postgresql://[^:]*:\([^@]*\)@.*|\1|p'"
echo ""
echo -e "${YELLOW}Connect with:${NC}"
echo "  psql -h localhost -p $LOCAL_PORT -U $DB_USER -d $DB_NAME"
echo ""
echo -e "${YELLOW}Or for Prisma Studio:${NC}"
echo "  DATABASE_URL=\"postgresql://$DB_USER:PASSWORD@localhost:$LOCAL_PORT/$DB_NAME\" bunx prisma studio"
echo ""
echo -e "Press ${RED}Ctrl+C${NC} to close the tunnel"
echo ""

aws ssm start-session \
    --target "$BASTION_ID" \
    --region "$REGION" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"$RDS_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
