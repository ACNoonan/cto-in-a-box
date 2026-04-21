#!/bin/bash
# =============================================================================
# DATABASE TUNNEL - Opens local connection to RDS via SSM bastion
# =============================================================================
# Creates a port-forwarding tunnel through the bastion host so you can connect
# to RDS from your local machine without exposing it to the public internet.
#
# Usage:
#   ./db-tunnel.sh                  # Prod tunnel on local port 5434
#   ./db-tunnel.sh --env dev        # Dev tunnel on local port 5434
#   ./db-tunnel.sh --env prod 5435  # Prod tunnel on custom local port
#
# Then connect with:
#   psql -h localhost -p 5434 -U {{DB_USER}} -d {{DB_NAME}}
# =============================================================================

set -e

# ==== CONFIGURATION (rendered by cto-bootstrap; tighten the TODOs once infra exists) ====

# Prod
PROD_RDS_HOST="{{PROD_RDS_HOST}}"
PROD_BASTION_NAME_TAG="{{PROD_BASTION_NAME_TAG}}"
PROD_DB_NAME="{{DB_NAME}}"
PROD_DB_SECRET_ID="{{DB_SECRET_ID}}"

# Dev
DEV_RDS_HOST="{{DEV_RDS_HOST}}"
DEV_BASTION_NAME_TAG="{{DEV_BASTION_NAME_TAG}}"
DEV_DB_NAME="{{DB_NAME}}_dev"
DEV_DB_SECRET_ID="{{DB_SECRET_ID_DEV}}"

# Shared
RDS_PORT="5432"
REGION="{{AWS_REGION}}"
DB_USER="{{DB_USER}}"
# =========================================================================================

# Parse arguments
ENV="prod"
LOCAL_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV="$2"
      shift 2
      ;;
    *)
      LOCAL_PORT="$1"
      shift
      ;;
  esac
done

LOCAL_PORT="${LOCAL_PORT:-5434}"

case "$ENV" in
  prod)
    RDS_HOST="$PROD_RDS_HOST"
    BASTION_NAME_TAG="$PROD_BASTION_NAME_TAG"
    DB_NAME="$PROD_DB_NAME"
    DB_SECRET_ID="$PROD_DB_SECRET_ID"
    ;;
  dev)
    RDS_HOST="$DEV_RDS_HOST"
    BASTION_NAME_TAG="$DEV_BASTION_NAME_TAG"
    DB_NAME="$DEV_DB_NAME"
    DB_SECRET_ID="$DEV_DB_SECRET_ID"
    ;;
  *)
    echo "Unknown environment: $ENV (use prod or dev)" >&2
    exit 1
    ;;
esac

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== RDS Tunnel via SSM ($ENV) ===${NC}"
echo ""

if [[ "$ENV" == "dev" ]]; then
  echo -e "${CYAN}Note: if dev and prod share an RDS instance, your IAM credentials"
  echo -e "must restrict access to dev databases only.${NC}"
  echo ""
fi

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
echo -e "${YELLOW}For Prisma Studio:${NC}"
echo "  DATABASE_URL=\"postgresql://$DB_USER:PASSWORD@localhost:$LOCAL_PORT/$DB_NAME\" bunx prisma studio"
echo ""
echo -e "Press ${RED}Ctrl+C${NC} to close the tunnel"
echo ""

aws ssm start-session \
    --target "$BASTION_ID" \
    --region "$REGION" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"$RDS_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
