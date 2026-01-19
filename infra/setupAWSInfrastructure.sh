#!/bin/bash

# ============================================================================
# AWS Infrastructure Setup Script
# ============================================================================
# Creates VPC, subnets, security groups, IAM roles, and EC2 instances
# for the Minecraft server infrastructure.
# ============================================================================

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aws-common.sh"

# Initialize
check_dependencies
load_project_vars
load_infra_settings

print_header "☁️  AWS Infrastructure Setup"

echo "📍 Region: $REGION"
echo "🔑 Key Pair: $KEY_NAME"
echo "📦 Storage: Proxy=${PROXY_STORAGE}GB, MC=${MC_STORAGE}GB ($VOL_TYPE)"

# ===== KEY PAIR =====
print_step "Checking Key Pair..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" > /dev/null 2>&1; then
    print_warning "Key Pair '$KEY_NAME' not found. Creating..."
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" \
        --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    print_success "Created Key Pair: ${KEY_NAME}.pem"
else
    print_success "Key Pair '$KEY_NAME' exists."
fi

# ===== VPC =====
print_step "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$REGION" \
    --query 'Vpc.VpcId' --output text)
tag_resource "$VPC_ID" "${PROJECT}-vpc" "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}' --region "$REGION"
update_config "vpc_id" "$VPC_ID"
print_success "VPC Created: $VPC_ID"

# ===== INTERNET GATEWAY =====
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
tag_resource "$IGW_ID" "${PROJECT}-igw" "$REGION"
update_config "internet_gateway_id" "$IGW_ID"

# ===== SUBNETS =====
print_step "Creating Subnets..."
PUB_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
    --availability-zone "${REGION}a" --region "$REGION" \
    --query 'Subnet.SubnetId' --output text)
tag_resource "$PUB_SUBNET_ID" "${PROJECT}-public-subnet" "$REGION"
aws ec2 modify-subnet-attribute --subnet-id "$PUB_SUBNET_ID" --map-public-ip-on-launch --region "$REGION"
update_config "public_subnet_id" "$PUB_SUBNET_ID"

PRI_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 \
    --availability-zone "${REGION}a" --region "$REGION" \
    --query 'Subnet.SubnetId' --output text)
tag_resource "$PRI_SUBNET_ID" "${PROJECT}-private-subnet" "$REGION"
update_config "private_subnet_id" "$PRI_SUBNET_ID"

# ===== ROUTE TABLES =====
RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$PUB_SUBNET_ID" \
    --region "$REGION" > /dev/null
tag_resource "$RT_ID" "${PROJECT}-public-rt" "$REGION"

# ===== NAT GATEWAY =====
print_step "Creating NAT Gateway..."
NAT_EIP_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" \
    --query 'AllocationId' --output text)
tag_resource "$NAT_EIP_ID" "${PROJECT}-nat-eip" "$REGION"
update_config "nat_eip_id" "$NAT_EIP_ID"

NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB_SUBNET_ID" \
    --allocation-id "$NAT_EIP_ID" --region "$REGION" \
    --query 'NatGateway.NatGatewayId' --output text)
tag_resource "$NAT_GW_ID" "${PROJECT}-nat-gw" "$REGION"
update_config "nat_gateway_id" "$NAT_GW_ID"

wait_with_message "Waiting for NAT Gateway..." \
    aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID" --region "$REGION"

# Private Route Table
PRI_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PRI_RT_ID" --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id "$NAT_GW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRI_RT_ID" --subnet-id "$PRI_SUBNET_ID" \
    --region "$REGION" > /dev/null
tag_resource "$PRI_RT_ID" "${PROJECT}-private-rt" "$REGION"

# ===== SECURITY GROUPS =====
print_step "Creating Security Groups..."
PROXY_SG_ID=$(aws ec2 create-security-group --group-name "${PROJECT}-proxy-sg" \
    --description "Security group for Proxy" --vpc-id "$VPC_ID" --region "$REGION" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" \
    --protocol tcp --port 25565 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" \
    --protocol tcp --port 25599 --cidr 0.0.0.0/0 --region "$REGION"
update_config "proxy_sg_id" "$PROXY_SG_ID"

MC_SG_ID=$(aws ec2 create-security-group --group-name "${PROJECT}-mc-sg" \
    --description "Security group for MC Server" --vpc-id "$VPC_ID" --region "$REGION" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$MC_SG_ID" \
    --protocol tcp --port 22 --source-group "$PROXY_SG_ID" --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$MC_SG_ID" \
    --protocol tcp --port 25565 --source-group "$PROXY_SG_ID" --region "$REGION"
update_config "mc_sg_id" "$MC_SG_ID"

# ===== IAM ROLE =====
print_step "Creating IAM Role..."
ROLE_NAME="${PROJECT}-proxy-role"
PROFILE_NAME="${PROJECT}-proxy-profile"

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

PROXY_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:StartInstances", "ec2:StopInstances"],
    "Resource": "*"
  }]
}'

aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" > /dev/null 2>&1 || true
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "${PROJECT}-proxy-policy" --policy-document "$PROXY_POLICY"
sleep 5

aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
update_config "iam_role_arn" "arn:aws:iam::account-id:role/$ROLE_NAME"
sleep 10

# ===== EC2 INSTANCES =====
print_step "Launching EC2 Instances..."

PROXY_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE_PROXY" \
    --key-name "$KEY_NAME" --subnet-id "$PUB_SUBNET_ID" --security-group-ids "$PROXY_SG_ID" \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$PROXY_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-proxy}]" \
    --region "$REGION" --query 'Instances[0].InstanceId' --output text)
update_config "proxy_instance_id" "$PROXY_ID"
print_success "Proxy Launched: $PROXY_ID"

MC_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE_MC" \
    --key-name "$KEY_NAME" --subnet-id "$PRI_SUBNET_ID" --security-group-ids "$MC_SG_ID" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$MC_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-mc-server}]" \
    --region "$REGION" --query 'Instances[0].InstanceId' --output text)
update_config "mc_instance_id" "$MC_ID"
print_success "MC Server Launched: $MC_ID"

wait_with_message "Waiting for instances to initialize..." \
    aws ec2 wait instance-running --instance-ids "$PROXY_ID" "$MC_ID" --region "$REGION"

# ===== ELASTIC IP =====
print_step "Allocating Elastic IP..."
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" \
    --query 'AllocationId' --output text)
tag_resource "$ALLOCATION_ID" "${PROJECT}-proxy-eip" "$REGION"
aws ec2 associate-address --instance-id "$PROXY_ID" --allocation-id "$ALLOCATION_ID" --region "$REGION"
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --region "$REGION" \
    --query 'Addresses[0].PublicIp' --output text)
update_config "proxy_allocation_id" "$ALLOCATION_ID"
print_success "Elastic IP Associated: $ELASTIC_IP"

# Store final IPs
PROXY_IP="$ELASTIC_IP"
MC_IP=$(aws ec2 describe-instances --instance-ids "$MC_ID" --region "$REGION" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
update_config "proxy_public_ip" "$PROXY_IP"
update_config "mc_private_ip" "$MC_IP"

print_header "🚀 Infrastructure Created Successfully"
echo "Proxy Public IP: $PROXY_IP"
echo "MC Private IP:   $MC_IP"
echo ""
echo "Configuration saved to $CONFIG_FILE"