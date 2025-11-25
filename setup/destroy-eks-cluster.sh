#!/bin/bash

set -e

echo "================================================"
echo "Destroying EKS Cluster and Resources"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Configuration
CLUSTER_NAME="argocd-training"
REGION="us-east-1"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    exit 1
fi

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    print_error "eksctl is not installed"
    exit 1
fi

# Verify AWS credentials
print_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS credentials verified (Account: ${ACCOUNT_ID})"

# Check if cluster exists
print_info "Checking if cluster exists..."
if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} &> /dev/null; then
    print_info "Cluster ${CLUSTER_NAME} does not exist. Skipping cluster deletion."
else
    print_info "Cluster ${CLUSTER_NAME} found"

    # Confirm deletion
    echo ""
    echo "⚠️  WARNING: This will delete the following resources:"
    echo "  - EKS Cluster: ${CLUSTER_NAME}"
    echo "  - All node groups and EC2 instances"
    echo "  - All Karpenter-provisioned nodes"
    echo "  - Load balancers and associated resources"
    echo "  - IAM roles and policies"
    echo ""
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cluster deletion cancelled."
        exit 0
    fi

    # Delete Karpenter NodePools first (this will drain nodes gracefully)
    print_info "Deleting Karpenter NodePools..."
    kubectl delete nodepools --all --ignore-not-found=true --timeout=5m 2>/dev/null || true
    print_success "NodePools deleted"

    # Delete EC2NodeClasses
    print_info "Deleting Karpenter EC2NodeClasses..."
    kubectl delete ec2nodeclasses --all --ignore-not-found=true --timeout=2m 2>/dev/null || true
    print_success "EC2NodeClasses deleted"

    # Wait a bit for Karpenter to clean up nodes
    print_info "Waiting for Karpenter to clean up nodes..."
    sleep 10

    # Uninstall Karpenter
    print_info "Uninstalling Karpenter..."
    helm uninstall karpenter -n kube-system 2>/dev/null || true
    print_success "Karpenter uninstalled"

    # Delete Load Balancers created by AWS Load Balancer Controller
    print_info "Cleaning up AWS Load Balancers..."
    LB_ARNS=$(aws elbv2 describe-load-balancers --region ${REGION} \
        --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}') || contains(to_string(Tags), '${CLUSTER_NAME}')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$LB_ARNS" ]; then
        for lb_arn in $LB_ARNS; do
            print_info "Deleting load balancer: ${lb_arn}"
            aws elbv2 delete-load-balancer --load-balancer-arn ${lb_arn} --region ${REGION} 2>/dev/null || true
        done
        print_success "Load balancers deleted"
        sleep 10
    else
        print_info "No load balancers found"
    fi

    # Delete Target Groups
    print_info "Cleaning up Target Groups..."
    TG_ARNS=$(aws elbv2 describe-target-groups --region ${REGION} \
        --query "TargetGroups[?contains(to_string(Tags), '${CLUSTER_NAME}')].TargetGroupArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$TG_ARNS" ]; then
        for tg_arn in $TG_ARNS; do
            print_info "Deleting target group: ${tg_arn}"
            aws elbv2 delete-target-group --target-group-arn ${tg_arn} --region ${REGION} 2>/dev/null || true
        done
        print_success "Target groups deleted"
    else
        print_info "No target groups found"
    fi

    # Delete Security Groups created by the cluster (wait a bit for LBs to be fully deleted)
    sleep 5
    print_info "Cleaning up Security Groups..."
    SG_IDS=$(aws ec2 describe-security-groups --region ${REGION} \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_IDS" ]; then
        for sg_id in $SG_IDS; do
            print_info "Deleting security group: ${sg_id}"
            aws ec2 delete-security-group --group-id ${sg_id} --region ${REGION} 2>/dev/null || true
        done
        print_success "Security groups deleted"
    else
        print_info "No additional security groups found"
    fi

    # Delete the cluster using eksctl (this will delete node groups, VPC, subnets, etc.)
    print_info "Deleting EKS cluster (this may take 10-15 minutes)..."
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${REGION} --wait

    print_success "EKS cluster deleted"
fi

# Clean up Karpenter IAM resources
print_info "Cleaning up Karpenter IAM resources..."

# Delete instance profile
if aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} --region ${REGION} &> /dev/null; then
    print_info "Removing role from instance profile..."
    aws iam remove-role-from-instance-profile \
        --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
        --role-name KarpenterNodeRole-${CLUSTER_NAME} \
        --region ${REGION} 2>/dev/null || true

    print_info "Deleting instance profile..."
    aws iam delete-instance-profile \
        --instance-profile-name KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
        --region ${REGION} 2>/dev/null || true

    print_success "Instance profile deleted"
else
    print_info "Instance profile not found"
fi

# Detach policies from Karpenter node role
if aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME} &> /dev/null; then
    print_info "Detaching policies from Karpenter node role..."
    aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true
    aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true
    aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
    aws iam detach-role-policy --role-name KarpenterNodeRole-${CLUSTER_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

    print_info "Deleting Karpenter node role..."
    aws iam delete-role --role-name KarpenterNodeRole-${CLUSTER_NAME} 2>/dev/null || true
    print_success "Karpenter node role deleted"
else
    print_info "Karpenter node role not found"
fi

# Delete AWS Load Balancer Controller IAM policy
print_info "Cleaning up AWS Load Balancer Controller IAM policy..."
POLICY_ARN=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy`].Arn' \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY_ARN" ]; then
    print_info "Deleting policy: ${POLICY_ARN}"
    aws iam delete-policy --policy-arn ${POLICY_ARN} 2>/dev/null || true
    print_success "Load balancer controller policy deleted"
else
    print_info "Load balancer controller policy not found"
fi

# Clean up any remaining EC2 instances with Karpenter tags
print_info "Checking for orphaned Karpenter nodes..."
INSTANCE_IDS=$(aws ec2 describe-instances --region ${REGION} \
    --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_IDS" ]; then
    print_info "Terminating orphaned instances: ${INSTANCE_IDS}"
    aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS} --region ${REGION} 2>/dev/null || true
    print_success "Orphaned instances terminated"
else
    print_info "No orphaned instances found"
fi

# Display summary
echo ""
echo "================================================"
print_success "Cleanup Complete!"
echo "================================================"
echo ""
echo "The following resources have been deleted:"
echo "  ✓ EKS Cluster: ${CLUSTER_NAME}"
echo "  ✓ All node groups and EC2 instances"
echo "  ✓ Karpenter resources (NodePools, nodes, IAM roles)"
echo "  ✓ Load balancers and target groups"
echo "  ✓ IAM policies and roles"
echo "  ✓ VPC, subnets, and security groups"
echo ""
echo "Note: Some resources may take a few minutes to fully delete."
echo "You can verify in the AWS Console."
echo ""
