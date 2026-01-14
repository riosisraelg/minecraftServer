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
    # Use a temporary file to avoid corruption during write
    tmp=$(mktemp)
    jq --arg val "$value" ".resources.$key = \$val" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "❌ 'jq' is not installed. Please install it (e.g., brew install jq)."
    exit 1
fi
if ! command -v aws &> /dev/null; then
    echo "❌ 'aws' CLI is not installed."
    exit 1
fi

echo "========================================="
echo "   ☁️  AWS Infrastructure Setup"
echo "========================================="

# Load Vars
PROJECT=$(read_config ".project")
REGION=$(read_config ".region")
AMI_ID=$(read_config ".ami_id")
INSTANCE_TYPE_PROXY=$(read_config ".instance_type_proxy")
INSTANCE_TYPE_MC=$(read_config ".instance_type_mc")
KEY_NAME=$(read_config ".key_name")
PROXY_STORAGE=$(read_config ".storage.proxy_size_gb")
MC_STORAGE=$(read_config ".storage.mc_size_gb")
VOL_TYPE=$(read_config ".storage.volume_type")

echo "📍 Region: $REGION"
echo "🔑 Key Pair: $KEY_NAME"
echo "📦 Storage: Proxy=${PROXY_STORAGE}GB, MC=${MC_STORAGE}GB ($VOL_TYPE)"

# Check/Create Key Pair
echo "SETUP: Checking Key Pair..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" > /dev/null 2>&1; then
    echo "   ⚠️  Key Pair '$KEY_NAME' not found. Creating it..."
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "   ✅ Created Key Pair: ${KEY_NAME}.pem (Saved in current directory)"
else
    echo "   ✅ Key Pair '$KEY_NAME' exists."
fi

# 1. VPC Setup
echo "SETUP: Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$REGION" --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${PROJECT}-vpc" --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames "{\"Value\":true}" --region "$REGION"
update_config "vpc_id" "$VPC_ID"
echo "✅ VPC Created: $VPC_ID"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value="${PROJECT}-igw" --region "$REGION"
update_config "internet_gateway_id" "$IGW_ID"

# Subnets
echo "SETUP: Creating Subnets..."
PUB_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "${REGION}a" --region "$REGION" --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$PUB_SUBNET_ID" --tags Key=Name,Value="${PROJECT}-public-subnet" --region "$REGION"
update_config "public_subnet_id" "$PUB_SUBNET_ID"

# Enable auto-assign public IP for public subnet
aws ec2 modify-subnet-attribute --subnet-id "$PUB_SUBNET_ID" --map-public-ip-on-launch --region "$REGION"

PRI_SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "${REGION}a" --region "$REGION" --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$PRI_SUBNET_ID" --tags Key=Name,Value="${PROJECT}-private-subnet" --region "$REGION"
update_config "private_subnet_id" "$PRI_SUBNET_ID"

# Route Table (Public)
RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$PUB_SUBNET_ID" --region "$REGION" > /dev/null
aws ec2 create-tags --resources "$RT_ID" --tags Key=Name,Value="${PROJECT}-public-rt" --region "$REGION"

# NAT Gateway (For Private Subnet Internet Access)
echo "SETUP: Creating NAT Gateway..."
NAT_EIP_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" --query 'AllocationId' --output text)
aws ec2 create-tags --resources "$NAT_EIP_ID" --tags Key=Name,Value="${PROJECT}-nat-eip" --region "$REGION"
update_config "nat_eip_id" "$NAT_EIP_ID"

NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB_SUBNET_ID" --allocation-id "$NAT_EIP_ID" --region "$REGION" --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources "$NAT_GW_ID" --tags Key=Name,Value="${PROJECT}-nat-gw" --region "$REGION"
update_config "nat_gateway_id" "$NAT_GW_ID"

echo "⏳ Waiting for NAT Gateway to be available (this takes a minute)..."
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID" --region "$REGION"

# Route Table (Private)
PRI_RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PRI_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRI_RT_ID" --subnet-id "$PRI_SUBNET_ID" --region "$REGION" > /dev/null
aws ec2 create-tags --resources "$PRI_RT_ID" --tags Key=Name,Value="${PROJECT}-private-rt" --region "$REGION"

# 2. Security Groups
echo "SETUP: Creating Security Groups..."
# Proxy SG
PROXY_SG_ID=$(aws ec2 create-security-group --group-name "${PROJECT}-proxy-sg" --description "Security group for Proxy" --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 25565 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$PROXY_SG_ID" --protocol tcp --port 25599 --cidr 0.0.0.0/0 --region "$REGION"
update_config "proxy_sg_id" "$PROXY_SG_ID"

# Minecraft SG
MC_SG_ID=$(aws ec2 create-security-group --group-name "${PROJECT}-mc-sg" --description "Security group for MC Server" --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
# Allow SSH and MC Only from Proxy SG
aws ec2 authorize-security-group-ingress --group-id "$MC_SG_ID" --protocol tcp --port 22 --source-group "$PROXY_SG_ID" --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$MC_SG_ID" --protocol tcp --port 25565 --source-group "$PROXY_SG_ID" --region "$REGION"
update_config "mc_sg_id" "$MC_SG_ID"

# 3. IAM Role
echo "SETUP: Creating IAM Role..."
ROLE_NAME="${PROJECT}-proxy-role"
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}'

PROXY_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:StartInstances",
                "ec2:StopInstances"
            ],
            "Resource": "*"
        }
    ]
}'

# Create Role if not exists
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" > /dev/null 2>&1 || echo "   Role likely exists, continuing..."

# Put Custom Policy (removes need for FullAccess)
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "${PROJECT}-proxy-policy" --policy-document "$PROXY_POLICY"

# Wait for eventual consistency
sleep 5

# Instance Profile
PROFILE_NAME="${PROJECT}-proxy-profile"
aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" > /dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" > /dev/null 2>&1 || true
update_config "iam_role_arn" "arn:aws:iam::account-id:role/$ROLE_NAME" # Store just name helps too
sleep 10 # Wait for profile propagation

# 4. Launch Instances
echo "SETUP: Launching EC2 Instances..."

# Launch Proxy
PROXY_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE_PROXY" \
    --key-name "$KEY_NAME" \
    --subnet-id "$PUB_SUBNET_ID" \
    --security-group-ids "$PROXY_SG_ID" \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$PROXY_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-proxy}]" \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)
update_config "proxy_instance_id" "$PROXY_ID"
echo "✅ Proxy Launched: $PROXY_ID"

# Launch MC Server
MC_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE_MC" \
    --key-name "$KEY_NAME" \
    --subnet-id "$PRI_SUBNET_ID" \
    --security-group-ids "$MC_SG_ID" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$MC_STORAGE,\"VolumeType\":\"$VOL_TYPE\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-mc-server}]" \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)
update_config "mc_instance_id" "$MC_ID"
echo "✅ MC Server Launched: $MC_ID"

echo "⏳ Waiting for instances to initialize..."
aws ec2 wait instance-running --instance-ids "$PROXY_ID" "$MC_ID" --region "$REGION"

# Elastic IP Setup for Proxy
echo "SETUP: Allocating and Associating Elastic IP to Proxy..."
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --region "$REGION" --query 'AllocationId' --output text)
aws ec2 create-tags --resources "$ALLOCATION_ID" --tags Key=Name,Value="${PROJECT}-proxy-eip" --region "$REGION"
aws ec2 associate-address --instance-id "$PROXY_ID" --allocation-id "$ALLOCATION_ID" --region "$REGION"
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --region "$REGION" --query 'Addresses[0].PublicIp' --output text)
update_config "proxy_allocation_id" "$ALLOCATION_ID"
echo "✅ Elastic IP Associated: $ELASTIC_IP"

# Get IPs
PROXY_IP="$ELASTIC_IP"
MC_IP=$(aws ec2 describe-instances --instance-ids "$MC_ID" --region "$REGION" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

update_config "proxy_public_ip" "$PROXY_IP"
update_config "mc_private_ip" "$MC_IP"

echo "========================================="
echo "   🚀 Infrastructure Created Successfully"
echo "========================================="
echo "Proxy Public IP: $PROXY_IP"
echo "MC Private IP:   $MC_IP"
echo ""
echo "Configuration saved to $CONFIG_FILE"