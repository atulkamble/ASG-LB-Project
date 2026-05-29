#!/bin/bash
# =============================================================================
# File        : cleanup-alb.sh
# Description : Deletes all AWS resources created by setup-alb.sh.
#
#               Resources removed (in safe dependency order):
#                 1. Deregister EC2 instances from the Target Group
#                 2. Delete the ALB listener (implicit — deletes with the ALB)
#                 3. Delete the Application Load Balancer
#                 4. Delete the Target Group
#                 5. Terminate the two EC2 instances
#
# Usage       : chmod +x cleanup-alb.sh && ./cleanup-alb.sh
#
# Note        : This script reads resource IDs from scripts/.alb-resources.env
#               which is generated automatically by setup-alb.sh.
#               If that file is missing, set the variables manually below.
# =============================================================================

set -euo pipefail

ENV_FILE="$(dirname "$0")/.alb-resources.env"

# Load resource IDs written by setup-alb.sh, or fall back to manual values
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  echo "[INFO] Loaded resource IDs from $ENV_FILE"
else
  echo "[WARN] $ENV_FILE not found. Set variables manually:"
  REGION="us-east-1"
  ALB_ARN=""       # arn:aws:elasticloadbalancing:...
  TG_ARN=""        # arn:aws:elasticloadbalancing:...
  INSTANCE_1=""    # i-xxxxxxxxxxxxxxxxx
  INSTANCE_2=""    # i-yyyyyyyyyyyyyyyyy

  if [[ -z "$ALB_ARN" || -z "$TG_ARN" ]]; then
    echo "[ERROR] ALB_ARN and TG_ARN must be set. Exiting."
    exit 1
  fi
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 1. Deregister instances from the Target Group (best-effort)
# ---------------------------------------------------------------------------
if [[ -n "${INSTANCE_1:-}" && -n "${INSTANCE_2:-}" ]]; then
  log "Deregistering instances from Target Group ..."
  aws elbv2 deregister-targets \
    --region "$REGION" \
    --target-group-arn "$TG_ARN" \
    --targets Id="$INSTANCE_1" Id="$INSTANCE_2" || true
fi

# ---------------------------------------------------------------------------
# 2. Delete the Application Load Balancer
#    Deleting the ALB also removes all its listeners automatically.
# ---------------------------------------------------------------------------
log "Deleting Application Load Balancer ..."
aws elbv2 delete-load-balancer \
  --region "$REGION" \
  --load-balancer-arn "$ALB_ARN"

log "Waiting for ALB to be deleted ..."
aws elbv2 wait load-balancers-deleted \
  --region "$REGION" \
  --load-balancer-arns "$ALB_ARN"
log "ALB deleted."

# ---------------------------------------------------------------------------
# 3. Delete the Target Group
#    Must be done after the ALB is deleted (a TG cannot be deleted while
#    it still has an active load balancer associated with it).
# ---------------------------------------------------------------------------
log "Deleting Target Group ..."
aws elbv2 delete-target-group \
  --region "$REGION" \
  --target-group-arn "$TG_ARN"
log "Target Group deleted."

# ---------------------------------------------------------------------------
# 4. Terminate the EC2 instances
# ---------------------------------------------------------------------------
if [[ -n "${INSTANCE_1:-}" && -n "${INSTANCE_2:-}" ]]; then
  log "Terminating EC2 instances ($INSTANCE_1, $INSTANCE_2) ..."
  aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_1" "$INSTANCE_2"

  log "Waiting for instances to terminate ..."
  aws ec2 wait instance-terminated \
    --region "$REGION" \
    --instance-ids "$INSTANCE_1" "$INSTANCE_2"
  log "Instances terminated."
fi

# ---------------------------------------------------------------------------
# 5. Remove the saved resource ID file
# ---------------------------------------------------------------------------
[[ -f "$ENV_FILE" ]] && rm "$ENV_FILE" && log "Removed $ENV_FILE"

log "============================================================"
log "Cleanup complete. All ALB resources have been removed."
log "============================================================"
