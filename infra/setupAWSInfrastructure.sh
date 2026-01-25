#!/bin/bash

# ============================================================================
# AWS Infrastructure Setup Script (Unified & Optimized)
# ============================================================================
# Creates a complete Minecraft Server Network Infrastructure on AWS.
# ============================================================================

set -e

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aws-common.sh"

# Initialize
check_dependencies
load_project_vars
load_infra_settings

print_header "☁️  Unified AWS Infrastructure Setup"
echo "📍 Region: $REGION"
echo "📦 Project: $PROJECT"
echo ""

# ============================================================================
# 1. NETWORK & VPC
# ============================================================================
print_header "🌐 1. Network Configuration"

# ----- VPC -----
print_step "Creating VPC..."
VPC_ID=$(aws_create "create-vpc" "vpc" "${PROJECT}-vpc" "Vpc.VpcId" --cidr-block 10.0.0.0/16)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' --region "$REGION"
update_config "vpc_id" "$VPC_ID"
print_success "VPC: $VPC_ID"

# ----- Internet Gateway -----
print_step "Creating Internet Gateway..."
IGW_ID=$(aws_create "create-internet-gateway" "internet-gateway" "${PROJECT}-igw" "InternetGateway.InternetGatewayId")
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
update_config "internet_gateway_id" "$IGW_ID"
print_success "IGW: $IGW_ID"

# ----- Subnets -----
print_step "Creating Subnets..."
# Public Subnet
PUB_SUBNET_ID=$(aws_create "create-subnet" "subnet" "${PROJECT}-public-subnet" "Subnet.SubnetId" \
    --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "${REGION}a")
aws ec2 modify-subnet-attribute --subnet-id "$PUB_SUBNET_ID" --map-public-ip-on-launch --region "$REGION"
update_config "public_subnet_id" "$PUB_SUBNET_ID"

# Private Subnet
PRI_SUBNET_ID=$(aws_create "create-subnet" "subnet" "${PROJECT}-private-subnet" "Subnet.SubnetId" \
    --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "${REGION}a")
update_config "private_subnet_id" "$PRI_SUBNET_ID"
print_success "Subnets Created"

# ----- Route Tables -----
print_step "Configuring Routing..."
# Public RT
PUB_RT_ID=$(aws_create "create-route-table" "route-table" "${PROJECT}-public-rt" "RouteTable.RouteTableId" --vpc-id "$VPC_ID")
aws ec2 create-route --route-table-id "$PUB_RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUB_RT_ID" --subnet-id "$PUB_SUBNET_ID" --region "$REGION" > /dev/null

# NAT Gateway (for Private Subnet)
print_step "Setting up NAT Gateway..."
NAT_EIP_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT}-nat-eip}]" \
    --query 'AllocationId' --output text)
update_config "nat_eip_id" "$NAT_EIP_ID"

NAT_GW_ID=$(aws_create "create-nat-gateway" "natgateway" "${PROJECT}-nat-gw" "NatGateway.NatGatewayId" \
    --subnet-id "$PUB_SUBNET_ID" --allocation-id "$NAT_EIP_ID")
update_config "nat_gateway_id" "$NAT_GW_ID"

wait_with_message "Waiting for NAT Gateway..." aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID" --region "$REGION"

# Private RT
PRI_RT_ID=$(aws_create "create-route-table" "route-table" "${PROJECT}-private-rt" "RouteTable.RouteTableId" --vpc-id "$VPC_ID")
aws ec2 create-route --route-table-id "$PRI_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRI_RT_ID" --subnet-id "$PRI_SUBNET_ID" --region "$REGION" > /dev/null
print_success "Routing Configured"

# ============================================================================
# 2. SECURITY GROUPS
# ============================================================================
print_header "🛡️  2. Security Groups"

# Proxy SG
PROXY_SG_ID=$(aws_create "create-security-group" "security-group" "${PROJECT}-proxy-sg" "GroupId" \
    --group-name "${PROJECT}-proxy-sg" --description "Proxy Security Group" --vpc-id "$VPC_ID")
update_config "proxy_sg_id" "$PROXY_SG_ID"

# Proxy Rules
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 25599 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 25565 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol udp --port 19132 --cidr 0.0.0.0/0 --region "$REGION" 2>/dev/null || true

# Backend SG
MC_SG_ID=$(aws_create "create-security-group" "security-group" "${PROJECT}-mc-sg" "GroupId" \
    --group-name "${PROJECT}-mc-sg" --description "Backend Security Group" --vpc-id "$VPC_ID")
update_config "mc_sg_id" "$MC_SG_ID"

# Backend Rules (Allow all from Proxy)
aws ec2 authorize-security-group-ingress --group-id "$MC_SG_ID" --protocol -1 --source-group "$PROXY_SG_ID" --region "$REGION"
print_success "Security Groups Created"

# ============================================================================
# 3. IAM ROLES
# ============================================================================
print_header "🔑 3. IAM Configuration"

ROLE_NAME="${PROJECT}-proxy-role"
PROFILE_NAME="${PROJECT}-proxy-profile"

TRUST_POLICY='{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Principal": { "Service": "ec2.amazonaws.com" },"Action": "sts:AssumeRole"}]}'
PROXY_POLICY='{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Action": ["ec2:DescribeInstances","ec2:DescribeInstanceStatus","ec2:StartInstances","ec2:StopInstances","ec2:DescribeSecurityGroups","ec2:AuthorizeSecurityGroupIngress","ec2:RevokeSecurityGroupIngress"],"Resource": "*"}]}'

aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" > /dev/null 2>&1 || true
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "${PROJECT}-proxy-policy" --policy-document "$PROXY_POLICY"
aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" > /dev/null 2>&1 || true

update_config "iam_role_arn" "arn:aws:iam::account-id:role/$ROLE_NAME"
print_waiting "Waiting for IAM propagation..."; sleep 15
print_success "IAM Ready"

# ============================================================================
# 4. EC2 INSTANCES
# ============================================================================
print_header "🖥️  4. Launching EC2 Instances"

# Key Pair
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" > /dev/null 2>&1; then
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    print_success "Created Key Pair: ${KEY_NAME}.pem"
fi

# Proxy Instance
print_step "Launching Proxy..."
PROXY_ID=$(aws_create "run-instances" "instance" "${PROJECT}-proxy" "Instances[0].InstanceId" \
    --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE_PROXY" \
    --key-name "$KEY_NAME" --subnet-id "$PUB_SUBNET_ID" --security-group-ids "$PROXY_SG_ID" \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$PROXY_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]")
update_config "proxy_instance_id" "$PROXY_ID"

# Backend Instance
print_step "Launching Backend..."
MC_ID=$(aws_create "run-instances" "instance" "${PROJECT}-mc-server" "Instances[0].InstanceId" \
    --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE_MC" \
    --key-name "$KEY_NAME" --subnet-id "$PRI_SUBNET_ID" --security-group-ids "$MC_SG_ID" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$MC_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]")
update_config "mc_instance_id" "$MC_ID"

wait_with_message "Waiting for instances..." aws ec2 wait instance-running --instance-ids "$PROXY_ID" "$MC_ID" --region "$REGION"

# ============================================================================
# 5. ELASTIC IP & FINALIZATION
# ============================================================================
print_header "🔗 5. Elastic IP Association"

EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT}-proxy-eip}]" \
    --query 'AllocationId' --output text)
update_config "proxy_allocation_id" "$EIP_ALLOC_ID"

aws ec2 associate-address --instance-id "$PROXY_ID" --allocation-id "$EIP_ALLOC_ID" --region "$REGION"
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids "$EIP_ALLOC_ID" --region "$REGION" --query 'Addresses[0].PublicIp' --output text)
update_config "proxy_public_ip" "$ELASTIC_IP"

MC_IP=$(aws ec2 describe-instances --instance-ids "$MC_ID" --region "$REGION" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
update_config "mc_private_ip" "$MC_IP"

print_header "✅ Setup Complete"
echo "   Proxy Public IP:  $ELASTIC_IP"
echo "   Backend Private IP: $MC_IP"
echo "   SSH Key: ${KEY_NAME}.pem"
echo ""