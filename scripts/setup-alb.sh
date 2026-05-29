#!/bin/bash
# =============================================================================
# File        : setup-alb.sh
# Description : Automates the creation of an AWS Application Load Balancer
#               (ALB) with two EC2 instances and a Target Group using the
#               AWS CLI.
#
#               Steps performed:
#                 1. Launch two Amazon Linux 2 t3.micro instances with Apache
#                    installed via User Data.
#                 2. Wait for both instances to reach the "running" state.
#                 3. Create a Target Group with HTTP health checks on /index.html
#                 4. Register both instances in the Target Group.
#                 5. Create an internet-facing Application Load Balancer.
#                 6. Add an HTTP listener (port 80) forwarding to the Target Group.
#                 7. Print the ALB DNS name to access the application.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured  (aws configure)
#   - IAM permissions: EC2 full access, ELB full access
#   - An existing key pair (set KEY_NAME below)
#   - An existing Security Group that allows TCP 22, 80, 443 (set SG_ID below)
#   - At least two public subnets in different AZs (set SUBNET_1 / SUBNET_2)
#
# Usage       : chmod +x setup-alb.sh && ./setup-alb.sh
#
# Cleanup     : Run scripts/cleanup-alb.sh to delete all resources created here.
# =============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# ---------------------------------------------------------------------------
# CONFIGURATION  — edit these variables before running the script
# ---------------------------------------------------------------------------
REGION="us-east-1"          # AWS region to deploy resources in
KEY_NAME="my-key"           # Name of an existing EC2 Key Pair (for SSH access)
SG_ID="sg-xxxxxxxx"         # Security Group ID allowing ports 22, 80, 443
SUBNET_1="subnet-xxxxxxxx"  # Public subnet in Availability Zone A
SUBNET_2="subnet-yyyyyyyy"  # Public subnet in Availability Zone B
AMI_ID="ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI (us-east-1); update per region
INSTANCE_TYPE="t3.micro"

# Resource naming
TG_NAME="my-target-group"
ALB_NAME="my-load-balancer"

# ---------------------------------------------------------------------------
# HELPER — print timestamped status messages
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 1. Launch two EC2 instances with the Apache user-data script
# ---------------------------------------------------------------------------
USER_DATA=$(base64 < "$(dirname "$0")/user-data.sh")

log "Launching EC2 instance 1 ..."
INSTANCE_1=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_1" \
  --associate-public-ip-address \
  --user-data "$USER_DATA" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=webserver-1}]' \
  --query 'Instances[0].InstanceId' \
  --output text)
log "Instance 1 ID: $INSTANCE_1"

log "Launching EC2 instance 2 ..."
INSTANCE_2=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_2" \
  --associate-public-ip-address \
  --user-data "$USER_DATA" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=webserver-2}]' \
  --query 'Instances[0].InstanceId' \
  --output text)
log "Instance 2 ID: $INSTANCE_2"

# ---------------------------------------------------------------------------
# 2. Wait for both instances to enter the "running" state
# ---------------------------------------------------------------------------
log "Waiting for instances to reach 'running' state (this may take ~60 s) ..."
aws ec2 wait instance-running \
  --region "$REGION" \
  --instance-ids "$INSTANCE_1" "$INSTANCE_2"
log "Both instances are running."

# Print public IPs for quick verification
PUBLIC_IP_1=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_1" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
PUBLIC_IP_2=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_2" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
log "Instance 1 public IP: http://$PUBLIC_IP_1"
log "Instance 2 public IP: http://$PUBLIC_IP_2"

# ---------------------------------------------------------------------------
# 3. Retrieve the VPC ID from the first instance (needed for Target Group)
# ---------------------------------------------------------------------------
VPC_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_1" \
  --query 'Reservations[0].Instances[0].VpcId' \
  --output text)
log "VPC ID: $VPC_ID"

# ---------------------------------------------------------------------------
# 4. Create a Target Group with health check on /index.html
# ---------------------------------------------------------------------------
log "Creating Target Group: $TG_NAME ..."
TG_ARN=$(aws elbv2 create-target-group \
  --region "$REGION" \
  --name "$TG_NAME" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --health-check-protocol HTTP \
  --health-check-path "/index.html" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --target-type instance \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)
log "Target Group ARN: $TG_ARN"

# ---------------------------------------------------------------------------
# 5. Register both instances with the Target Group
# ---------------------------------------------------------------------------
log "Registering instances with the Target Group ..."
aws elbv2 register-targets \
  --region "$REGION" \
  --target-group-arn "$TG_ARN" \
  --targets Id="$INSTANCE_1" Id="$INSTANCE_2"
log "Instances registered."

# ---------------------------------------------------------------------------
# 6. Create an internet-facing Application Load Balancer
# ---------------------------------------------------------------------------
log "Creating Application Load Balancer: $ALB_NAME ..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --region "$REGION" \
  --name "$ALB_NAME" \
  --subnets "$SUBNET_1" "$SUBNET_2" \
  --security-groups "$SG_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)
log "ALB ARN: $ALB_ARN"

# ---------------------------------------------------------------------------
# 7. Add an HTTP listener on port 80 forwarding traffic to the Target Group
# ---------------------------------------------------------------------------
log "Creating HTTP listener on port 80 ..."
aws elbv2 create-listener \
  --region "$REGION" \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" > /dev/null
log "Listener created."

# ---------------------------------------------------------------------------
# 8. Print the ALB DNS name
# ---------------------------------------------------------------------------
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

log "============================================================"
log "Setup complete!"
log "Load Balancer URL : http://$ALB_DNS"
log "Refresh the URL multiple times to see traffic split across"
log "both instances (different hostnames in the response)."
log "============================================================"

# Save resource IDs for the cleanup script
cat > "$(dirname "$0")/.alb-resources.env" <<EOF
REGION=$REGION
ALB_ARN=$ALB_ARN
TG_ARN=$TG_ARN
INSTANCE_1=$INSTANCE_1
INSTANCE_2=$INSTANCE_2
EOF
log "Resource IDs saved to scripts/.alb-resources.env (used by cleanup-alb.sh)"
