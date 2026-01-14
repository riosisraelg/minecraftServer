#!/bin/bash

# Configuration
CONFIG_FILE="infra/awsConfig.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found at $CONFIG_FILE"
    exit 1
fi

# Helper function to read config
read_config() {
    jq -r "$1" "$CONFIG_FILE"
}

# Helper function to update config
update_config() {
    local key="$1"
    local value="$2"
    tmp=$(mktemp)
    jq --arg val "$value" ".resources.$key = \$val" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

echo "========================================="
echo "   🗑️  AWS Infrastructure Cleanup"
echo "========================================="

# Load Vars
PROJECT=$(read_config ".project")
REGION=$(read_config ".region")
VPC_ID=$(read_config ".resources.vpc_id")
PUB_SUBNET_ID=$(read_config ".resources.public_subnet_id")
PRI_SUBNET_ID=$(read_config ".resources.private_subnet_id")
IGW_ID=$(read_config ".resources.internet_gateway_id")
NAT_GW_ID=$(read_config ".resources.nat_gateway_id")
NAT_EIP_ID=$(read_config ".resources.nat_eip_id")
PROXY_SG_ID=$(read_config ".resources.proxy_sg_id")
MC_SG_ID=$(read_config ".resources.mc_sg_id")
ALLOCATION_ID=$(read_config ".resources.proxy_allocation_id")
IAM_ROLE_ARN=$(read_config ".resources.iam_role_arn")
PROXY_INSTANCE_ID=$(read_config ".resources.proxy_instance_id")
MC_INSTANCE_ID=$(read_config ".resources.mc_instance_id")

echo "📍 Region: $REGION"
echo "🔍 Reading configuration from $CONFIG_FILE"

# 1. Terminate Instances
echo "CLEANUP: Terminating Instances..."
# Collect instance IDs from config, or find by tag if config is empty (fail-safe)
IDS_TO_TERMINATE=""

if [ "$PROXY_INSTANCE_ID" != "" ] && [ "$PROXY_INSTANCE_ID" != "null" ]; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $PROXY_INSTANCE_ID"
fi
if [ "$MC_INSTANCE_ID" != "" ] && [ "$MC_INSTANCE_ID" != "null" ]; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $MC_INSTANCE_ID"
fi

# Also check tags just in case config didn't save
TAGGED_INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PROJECT}-proxy,${PROJECT}-mc-server" "Name=instance-state-name,Values=running,pending,stopped,stopping" --region "$REGION" --query "Reservations[].Instances[].InstanceId" --output text)
if [ ! -z "$TAGGED_INSTANCES" ]; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $TAGGED_INSTANCES"
fi

# Remove duplicates
IDS_TO_TERMINATE=$(echo "$IDS_TO_TERMINATE" | tr ' ' '\n' | sort -u | xargs)

if [ ! -z "$IDS_TO_TERMINATE" ]; then
    echo "   Terminating: $IDS_TO_TERMINATE"
    aws ec2 terminate-instances --instance-ids $IDS_TO_TERMINATE --region "$REGION" > /dev/null
    echo "   ⏳ Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --instance-ids $IDS_TO_TERMINATE --region "$REGION"
    echo "   ✅ Instances terminated."
else
    echo "   ℹ️  No instances found to terminate."
fi

update_config "proxy_instance_id" ""
update_config "mc_instance_id" ""
update_config "proxy_public_ip" ""
update_config "mc_private_ip" ""

# 2. Release Elastic IP
if [ "$ALLOCATION_ID" != "" ] && [ "$ALLOCATION_ID" != "null" ]; then
    echo "CLEANUP: Releasing Elastic IP ($ALLOCATION_ID)..."
    aws ec2 release-address --allocation-id "$ALLOCATION_ID" --region "$REGION" > /dev/null 2>&1 || echo "   ⚠️  Could not release IP (maybe already gone)"
    update_config "proxy_allocation_id" ""
else
    echo "   ℹ️  No Elastic IP to release."
fi

# 3. IAM Role & Profile
echo "CLEANUP: Deleting IAM Resources..."
ROLE_NAME="${PROJECT}-proxy-role"
PROFILE_NAME="${PROJECT}-proxy-profile"

# Remove Role from Profile
aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
# Delete Profile
aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1 || true
# Detach Policies
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess > /dev/null 2>&1 || true
# Delete Role
aws iam delete-role --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
update_config "iam_role_arn" ""

# 4. Security Groups
echo "CLEANUP: Deleting Security Groups..."
# Need to wait a bit if instances just terminated for ENIs to release
sleep 5

# Delete MC SG first (dependent on Proxy SG?) 
# Actually MC SG allows ingress FROM Proxy SG. So MC SG doesn't depend on Proxy SG, but Proxy SG might be referenced by MC SG rules.
# If MC SG has a rule "Allow from Proxy SG", we must delete that rule or the MC SG first? 
# Correct: Delete MC SG first.
if [ "$MC_SG_ID" != "" ] && [ "$MC_SG_ID" != "null" ]; then
    echo "   Deleting MC SG ($MC_SG_ID)..."
    aws ec2 delete-security-group --group-id "$MC_SG_ID" --region "$REGION" > /dev/null 2>&1 || echo "   ⚠️  Failed to delete MC SG (check dependencies)"
    update_config "mc_sg_id" ""
fi

if [ "$PROXY_SG_ID" != "" ] && [ "$PROXY_SG_ID" != "null" ]; then
    echo "   Deleting Proxy SG ($PROXY_SG_ID)..."
    aws ec2 delete-security-group --group-id "$PROXY_SG_ID" --region "$REGION" > /dev/null 2>&1 || echo "   ⚠️  Failed to delete Proxy SG"
    update_config "proxy_sg_id" ""
fi

# 5. Subnets & Route Tables
echo "CLEANUP: Deleting Network Components..."
# Find Custom Route Table
RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${PROJECT}-public-rt" --region "$REGION" --query "RouteTables[0].RouteTableId" --output text)
if [ "$RT_ID" != "None" ] && [ "$RT_ID" != "" ]; then
    # Disassociate first
    echo "   Disassociating Route Table ($RT_ID)..."
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$RT_ID" --region "$REGION" --query "RouteTables[].Associations[].RouteTableAssociationId" --output text)
    for assoc in $ASSOC_IDS; do
        if [ "$assoc" != "None" ]; then
           aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" > /dev/null 2>&1
        fi
    done
    echo "   Deleting Route Table ($RT_ID)..."
    aws ec2 delete-route-table --route-table-id "$RT_ID" --region "$REGION" > /dev/null 2>&1
fi

# Find Private Route Table
PRI_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${PROJECT}-private-rt" --region "$REGION" --query "RouteTables[0].RouteTableId" --output text)
if [ "$PRI_RT_ID" != "None" ] && [ "$PRI_RT_ID" != "" ]; then
    echo "   Disassociating Private Route Table ($PRI_RT_ID)..."
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$PRI_RT_ID" --region "$REGION" --query "RouteTables[].Associations[].RouteTableAssociationId" --output text)
    for assoc in $ASSOC_IDS; do
        if [ "$assoc" != "None" ]; then
           aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" > /dev/null 2>&1
        fi
    done
    echo "   Deleting Private Route Table ($PRI_RT_ID)..."
    aws ec2 delete-route-table --route-table-id "$PRI_RT_ID" --region "$REGION" > /dev/null 2>&1
fi

# 5.5 NAT Gateway (Must be deleted before Elastic IP release and before VPC delete)
if [ "$NAT_GW_ID" != "" ] && [ "$NAT_GW_ID" != "null" ]; then
    echo "CLEANUP: Deleting NAT Gateway ($NAT_GW_ID)..."
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GW_ID" --region "$REGION" > /dev/null 2>&1
    echo "   ⏳ Waiting for NAT Gateway to delete (this takes a minute)..."
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_GW_ID" --region "$REGION"
    update_config "nat_gateway_id" ""
fi

# Release NAT Elastic IP
if [ "$NAT_EIP_ID" != "" ] && [ "$NAT_EIP_ID" != "null" ]; then
    echo "CLEANUP: Releasing NAT Elastic IP ($NAT_EIP_ID)..."
    aws ec2 release-address --allocation-id "$NAT_EIP_ID" --region "$REGION" > /dev/null 2>&1 || echo "   ⚠️  Could not release NAT IP"
    update_config "nat_eip_id" ""
fi

if [ "$PUB_SUBNET_ID" != "" ] && [ "$PUB_SUBNET_ID" != "null" ]; then
    echo "   Deleting Public Subnet ($PUB_SUBNET_ID)..."
    aws ec2 delete-subnet --subnet-id "$PUB_SUBNET_ID" --region "$REGION" > /dev/null 2>&1
    update_config "public_subnet_id" ""
fi

if [ "$PRI_SUBNET_ID" != "" ] && [ "$PRI_SUBNET_ID" != "null" ]; then
    echo "   Deleting Private Subnet ($PRI_SUBNET_ID)..."
    aws ec2 delete-subnet --subnet-id "$PRI_SUBNET_ID" --region "$REGION" > /dev/null 2>&1
    update_config "private_subnet_id" ""
fi

# 6. Internet Gateway
if [ "$IGW_ID" != "" ] && [ "$IGW_ID" != "null" ]; then
    echo "   Deleting Internet Gateway ($IGW_ID)..."
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" > /dev/null 2>&1 || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION" > /dev/null 2>&1 
    update_config "internet_gateway_id" ""
fi

# 7. VPC
if [ "$VPC_ID" != "" ] && [ "$VPC_ID" != "null" ]; then
    echo "CLEANUP: Deleting VPC ($VPC_ID)..."
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" > /dev/null 2>&1 || echo "   ⚠️  Failed to delete VPC (check for remaining dependencies like ENIs or SGs)"
    update_config "vpc_id" ""
fi

echo "========================================="
echo "   ✨ Cleanup Complete"
echo "========================================="
