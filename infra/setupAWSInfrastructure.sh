#!/usr/bin/env bash

# Obatin ID

## VPC ID

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=minecraftServer-vpc" \
    --query "Vpcs[*].VpcId" \
    --output text)

## Subnet ID

SUBNET_PUBLIC1_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=minecraftServer-subnet-public1-mx-central-1a" \
    --query "Subnets[*].SubnetId" \
    --output text)

SUBNET_PRIVATE1_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=minecraftServer-subnet-private1-mx-central-1a" \
    --query "Subnets[*].SubnetId" \
    --output text)

## Route Table ID

ROUTE_TABLE_PUBLIC1_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=minecraftServer-rtb-public" \
    --query "RouteTables[*].RouteTableId" \
    --output text)

## Security Group ID

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=minecraftServer-sg" \
    --query "SecurityGroups[*].GroupId" \
    --output text)

## Key Pair

KEY_PAIR_ID=$(aws ec2 describe-key-pairs \
    --filters "Name=key-name,Values=mcServer-kp" \
    --query "KeyPairs[*].KeyPairId" \
    --output text)


# Create Infrastructure

AMI_ID=$(aws ec2 describe-images \
    --region mx-central-1 \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-arm64" "Name=state,Values=available" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)

## Launch EC2 Instances with AMI

### Proxy Server

aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t4g.small\
    --key-name mcServer-kp \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_PUBLIC1_ID \
    --associate-public-ip-address \
    --user-data file://user-data-proxy-server.sh

EC2_PROXY_SERVER_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=minecraftServer-proxy-server" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

### Minecraft Server

aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t4g.large \
    --key-name mcServer-kp \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_PRIVATE1_ID \
    --user-data file://user-data-minecraft-server.sh

EC2_PROXY_SERVER_ID=$(aws ec2 describe-instances)