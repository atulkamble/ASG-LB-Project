#!/bin/bash
# =============================================================================
# File        : setup-asg.sh
# Description : Automates the creation of an AWS Auto Scaling Group (ASG)
#               backed by an Application Load Balancer (ALB) using the AWS CLI.
#
#               Steps performed:
#                 1. Create an EC2 Launch Template with Apache user data.
#                 2. Create a Target Group with HTTP health checks.
#                 3. Create an internet-facing Application Load Balancer.
#                 4. Add an HTTP listener forwarding traffic to the Target Group.
#                 5. Create an Auto Scaling Group (min 1, desired 2, max 3)
#                    attached to the ALB Target Group.
#                 6. Print the ALB DNS name.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured  (aws configure)
#   - IAM permissions: EC2 full access, ELB full access, AutoScaling full access
#   - An existing key pair          (set KEY_NAME below)
#   - An existing Security Group    (set SG_ID below)    — allow TCP 22, 80, 443
#   - At least two public subnets in different AZs (SUBNET_1 / SUBNET_2)
#
# Usage       : chmod +x setup-asg.sh && ./setup-asg.sh
#
# Cleanup     : Run scripts/cleanup-asg.sh to delete all resources created here.
# =============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# ---------------------------------------------------------------------------
# CONFIGURATION  — edit these variables before running the script
# ---------------------------------------------------------------------------
REGION="us-east-1"
KEY_NAME="my-key"               # Existing EC2 Key Pair name
SG_ID="sg-xxxxxxxx"             # Security Group ID (ports 22, 80, 443)
SUBNET_1="subnet-xxxxxxxx"      # Public subnet in AZ-A
SUBNET_2="subnet-yyyyyyyy"      # Public subnet in AZ-B
AMI_ID="ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI (us-east-1); update per region
INSTANCE_TYPE="t3.micro"

# Auto Scaling Group capacity settings
ASG_MIN=1       # Minimum number of running instances
ASG_DESIRED=2   # Initial desired number of instances
ASG_MAX=3       # Maximum number of instances the ASG can scale out to

# Resource naming
TEMPLATE_NAME="webserver-launch-template"
TG_NAME="asg-target-group"
ALB_NAME="my-asg-alb"
ASG_NAME="myASG"

# ---------------------------------------------------------------------------
# HELPER — print timestamped status messages
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# 1. Create an EC2 Launch Template
#    The Launch Template defines the blueprint for every instance the ASG
#    launches — AMI, instance type, key pair, security group, and user data.
# ---------------------------------------------------------------------------
log "Encoding user-data script ..."
# The user-data must be base64-encoded when passed to the Launch Template API
USER_DATA_B64=$(base64 < "$(dirname "$0")/user-data.sh")

log "Creating Launch Template: $TEMPLATE_NAME ..."
TEMPLATE_ID=$(aws ec2 create-launch-template \
  --region "$REGION" \
  --launch-template-name "$TEMPLATE_NAME" \
  --version-description "v1 - Apache web server" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"KeyName\": \"$KEY_NAME\",
    \"SecurityGroupIds\": [\"$SG_ID\"],
    \"UserData\": \"$USER_DATA_B64\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [{\"Key\": \"Name\", \"Value\": \"asg-webserver\"}]
    }]
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)
log "Launch Template ID: $TEMPLATE_ID"

# ---------------------------------------------------------------------------
# 2. Retrieve the VPC ID from the first subnet (needed for Target Group)
# ---------------------------------------------------------------------------
VPC_ID=$(aws ec2 describe-subnets \
  --region "$REGION" \
  --subnet-ids "$SUBNET_1" \
  --query 'Subnets[0].VpcId' \
  --output text)
log "VPC ID: $VPC_ID"

# ---------------------------------------------------------------------------
# 3. Create a Target Group
#    The Target Group receives traffic from the ALB and forwards it to
#    healthy EC2 instances. Health checks run against /index.html.
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
# 4. Create an internet-facing Application Load Balancer
#    Spans both subnets/AZs for high availability.
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
# 5. Add an HTTP listener on port 80
#    All HTTP traffic arriving at the ALB is forwarded to the Target Group.
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
# 6. Create the Auto Scaling Group
#    The ASG uses the Launch Template to spin up instances across both
#    subnets and automatically registers them with the ALB Target Group.
# ---------------------------------------------------------------------------
log "Creating Auto Scaling Group: $ASG_NAME ..."
aws autoscaling create-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=$TEMPLATE_ID,Version=\$Latest" \
  --min-size "$ASG_MIN" \
  --desired-capacity "$ASG_DESIRED" \
  --max-size "$ASG_MAX" \
  --vpc-zone-identifier "$SUBNET_1,$SUBNET_2" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 120
log "ASG created with min=$ASG_MIN / desired=$ASG_DESIRED / max=$ASG_MAX."

# ---------------------------------------------------------------------------
# 7. Print the ALB DNS name
# ---------------------------------------------------------------------------
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

log "============================================================"
log "Setup complete!"
log "Load Balancer URL  : http://$ALB_DNS"
log "Auto Scaling Group : $ASG_NAME"
log "  Min / Desired / Max : $ASG_MIN / $ASG_DESIRED / $ASG_MAX"
log ""
log "To test self-healing: manually terminate an instance from"
log "the EC2 console. The ASG will automatically replace it."
log "============================================================"

# Save resource IDs so the cleanup script can reference them
cat > "$(dirname "$0")/.asg-resources.env" <<EOF
REGION=$REGION
ASG_NAME=$ASG_NAME
TEMPLATE_ID=$TEMPLATE_ID
TEMPLATE_NAME=$TEMPLATE_NAME
ALB_ARN=$ALB_ARN
TG_ARN=$TG_ARN
EOF
log "Resource IDs saved to scripts/.asg-resources.env (used by cleanup-asg.sh)"
