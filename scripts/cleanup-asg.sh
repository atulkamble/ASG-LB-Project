#!/bin/bash
# =============================================================================
# File        : cleanup-asg.sh
# Description : Deletes all AWS resources created by setup-asg.sh.
#
#               Resources removed (in safe dependency order):
#                 1. Delete the Auto Scaling Group (terminates managed instances)
#                 2. Delete the Application Load Balancer (and its listeners)
#                 3. Delete the Target Group
#                 4. Delete the EC2 Launch Template
#
# Usage       : chmod +x cleanup-asg.sh && ./cleanup-asg.sh
#
# Note        : This script reads resource IDs from scripts/.asg-resources.env
#               which is generated automatically by setup-asg.sh.
#               If that file is missing, set the variables manually below.
# =============================================================================

set -euo pipefail

ENV_FILE="$(dirname "$0")/.asg-resources.env"

# Load resource IDs written by setup-asg.sh, or fall back to manual values
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  echo "[INFO] Loaded resource IDs from $ENV_FILE"
else
  echo "[WARN] $ENV_FILE not found. Set variables manually:"
  REGION="us-east-1"
  ASG_NAME="myASG"
  TEMPLATE_ID=""       # lt-xxxxxxxxxxxxxxxxx
  TEMPLATE_NAME="webserver-launch-template"
  ALB_ARN=""           # arn:aws:elasticloadbalancing:...
  TG_ARN=""            # arn:aws:elasticloadbalancing:...

  if [[ -z "$ALB_ARN" || -z "$TG_ARN" ]]; then
    echo "[ERROR] ALB_ARN and TG_ARN must be set. Exiting."
    exit 1
  fi
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 1. Delete the Auto Scaling Group
#    Using --force-delete terminates all running instances managed by the
#    ASG immediately, without waiting for scale-in lifecycle hooks.
# ---------------------------------------------------------------------------
log "Deleting Auto Scaling Group: $ASG_NAME ..."
aws autoscaling delete-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --force-delete || true   # Ignore error if ASG no longer exists

log "Waiting for ASG instances to terminate (this may take ~2 min) ..."
# Poll until no instances with the ASG tag remain in a non-terminated state
while true; do
  COUNT=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'length(Reservations[].Instances[])' \
    --output text)
  [[ "$COUNT" -eq 0 ]] && break
  log "  $COUNT instance(s) still active, waiting 15 s ..."
  sleep 15
done
log "All ASG instances terminated."

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
#    The ALB must be fully deleted before this step can succeed.
# ---------------------------------------------------------------------------
log "Deleting Target Group ..."
aws elbv2 delete-target-group \
  --region "$REGION" \
  --target-group-arn "$TG_ARN"
log "Target Group deleted."

# ---------------------------------------------------------------------------
# 4. Delete the EC2 Launch Template
# ---------------------------------------------------------------------------
log "Deleting Launch Template: $TEMPLATE_NAME ..."
aws ec2 delete-launch-template \
  --region "$REGION" \
  --launch-template-id "$TEMPLATE_ID" || \
aws ec2 delete-launch-template \
  --region "$REGION" \
  --launch-template-name "$TEMPLATE_NAME" || true
log "Launch Template deleted."

# ---------------------------------------------------------------------------
# 5. Remove the saved resource ID file
# ---------------------------------------------------------------------------
[[ -f "$ENV_FILE" ]] && rm "$ENV_FILE" && log "Removed $ENV_FILE"

log "============================================================"
log "Cleanup complete. All ASG + ALB resources have been removed."
log "============================================================"
