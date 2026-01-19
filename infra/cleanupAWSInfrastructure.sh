#!/bin/bash

# ============================================================================
# AWS Infrastructure Cleanup Script
# ============================================================================
# Removes all AWS resources created by setupAWSInfrastructure.sh
# ============================================================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aws-common.sh"

# Initialize
check_dependencies
load_project_vars
load_resource_vars

print_header "🗑️  AWS Infrastructure Cleanup"

echo "📍 Region: $REGION"
echo "🔍 Reading configuration from $CONFIG_FILE"

# ===== TERMINATE INSTANCES =====
print_cleanup "Terminating Instances..."
IDS_TO_TERMINATE=""

if is_valid_id "$PROXY_INSTANCE_ID"; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $PROXY_INSTANCE_ID"
fi
if is_valid_id "$MC_INSTANCE_ID"; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $MC_INSTANCE_ID"
fi

# Also check by tags as fallback
TAGGED_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT}-proxy,${PROJECT}-mc-server" \
              "Name=instance-state-name,Values=running,pending,stopped,stopping" \
    --region "$REGION" --query "Reservations[].Instances[].InstanceId" --output text)

if [ -n "$TAGGED_INSTANCES" ]; then
    IDS_TO_TERMINATE="$IDS_TO_TERMINATE $TAGGED_INSTANCES"
fi

# Remove duplicates
IDS_TO_TERMINATE=$(echo "$IDS_TO_TERMINATE" | tr ' ' '\n' | sort -u | xargs)

if [ -n "$IDS_TO_TERMINATE" ]; then
    echo "   Terminating: $IDS_TO_TERMINATE"
    aws ec2 terminate-instances --instance-ids $IDS_TO_TERMINATE --region "$REGION" > /dev/null
    wait_with_message "Waiting for instances to terminate..." \
        aws ec2 wait instance-terminated --instance-ids $IDS_TO_TERMINATE --region "$REGION"
    print_success "Instances terminated."
else
    print_info "No instances found to terminate."
fi

clear_config "proxy_instance_id"
clear_config "mc_instance_id"
clear_config "proxy_public_ip"
clear_config "mc_private_ip"

# ===== RELEASE ELASTIC IP =====
if is_valid_id "$ALLOCATION_ID"; then
    print_cleanup "Releasing Elastic IP ($ALLOCATION_ID)..."
    aws ec2 release-address --allocation-id "$ALLOCATION_ID" --region "$REGION" > /dev/null 2>&1 || \
        print_warning "Could not release IP (maybe already gone)"
    clear_config "proxy_allocation_id"
else
    print_info "No Elastic IP to release."
fi

# ===== IAM RESOURCES =====
print_cleanup "Deleting IAM Resources..."
ROLE_NAME="${PROJECT}-proxy-role"
PROFILE_NAME="${PROJECT}-proxy-profile"

aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1 || true
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "${PROJECT}-proxy-policy" > /dev/null 2>&1 || true
aws iam delete-role --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
clear_config "iam_role_arn"

# ===== SECURITY GROUPS =====
print_cleanup "Deleting Security Groups..."
sleep 5  # Wait for ENIs to release

if is_valid_id "$MC_SG_ID"; then
    echo "   Deleting MC SG ($MC_SG_ID)..."
    safe_delete_sg "$MC_SG_ID" "$REGION"
    clear_config "mc_sg_id"
fi

if is_valid_id "$PROXY_SG_ID"; then
    echo "   Deleting Proxy SG ($PROXY_SG_ID)..."
    safe_delete_sg "$PROXY_SG_ID" "$REGION"
    clear_config "proxy_sg_id"
fi

# ===== ROUTE TABLES =====
print_cleanup "Deleting Network Components..."

# Helper function to delete route table
delete_route_table() {
    local rt_name="$1"
    local rt_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$rt_name" \
        --region "$REGION" --query "RouteTables[0].RouteTableId" --output text)
    
    if is_valid_id "$rt_id"; then
        echo "   Disassociating Route Table ($rt_id)..."
        local assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" \
            --region "$REGION" --query "RouteTables[].Associations[].RouteTableAssociationId" --output text)
        for assoc in $assoc_ids; do
            if is_valid_id "$assoc"; then
                aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" > /dev/null 2>&1
            fi
        done
        echo "   Deleting Route Table ($rt_id)..."
        aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION" > /dev/null 2>&1
    fi
}

delete_route_table "${PROJECT}-public-rt"
delete_route_table "${PROJECT}-private-rt"

# ===== NAT GATEWAY =====
if is_valid_id "$NAT_GW_ID"; then
    print_cleanup "Deleting NAT Gateway ($NAT_GW_ID)..."
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GW_ID" --region "$REGION" > /dev/null 2>&1
    wait_with_message "Waiting for NAT Gateway to delete..." \
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_GW_ID" --region "$REGION"
    clear_config "nat_gateway_id"
fi

# Release NAT Elastic IP
if is_valid_id "$NAT_EIP_ID"; then
    print_cleanup "Releasing NAT Elastic IP ($NAT_EIP_ID)..."
    aws ec2 release-address --allocation-id "$NAT_EIP_ID" --region "$REGION" > /dev/null 2>&1 || \
        print_warning "Could not release NAT IP"
    clear_config "nat_eip_id"
fi

# ===== SUBNETS =====
if is_valid_id "$PUB_SUBNET_ID"; then
    echo "   Deleting Public Subnet ($PUB_SUBNET_ID)..."
    aws ec2 delete-subnet --subnet-id "$PUB_SUBNET_ID" --region "$REGION" > /dev/null 2>&1
    clear_config "public_subnet_id"
fi

if is_valid_id "$PRI_SUBNET_ID"; then
    echo "   Deleting Private Subnet ($PRI_SUBNET_ID)..."
    aws ec2 delete-subnet --subnet-id "$PRI_SUBNET_ID" --region "$REGION" > /dev/null 2>&1
    clear_config "private_subnet_id"
fi

# ===== INTERNET GATEWAY =====
if is_valid_id "$IGW_ID"; then
    echo "   Deleting Internet Gateway ($IGW_ID)..."
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" > /dev/null 2>&1 || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION" > /dev/null 2>&1
    clear_config "internet_gateway_id"
fi

# ===== VPC =====
if is_valid_id "$VPC_ID"; then
    print_cleanup "Deleting VPC ($VPC_ID)..."
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" > /dev/null 2>&1 || \
        print_warning "Failed to delete VPC (check for remaining dependencies)"
    clear_config "vpc_id"
fi

print_header "✨ Cleanup Complete"
