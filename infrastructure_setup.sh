#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "======================================================================================================"
echo "Updating System ...."
# Update the system and install necessary tools
sudo yum update -y
sudo yum install -y git nodejs npm yum-utils

echo "======================================================================================================"
echo "Installing Terraform ...."
# Add the HashiCorp AMI repository
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
#Installing Terraform
sudo yum -y install terraform
# Checking if terraform is installed
terraform version
echo "======================================================================================================"

echo "Initializing Terraform and Creating required resources ..."
# Create resources with Terraform
cd terraform

# Initialize Terraform
terraform init

# Plan the changes to be made by Terraform
terraform plan

# Apply Terraform configurations
terraform apply -auto-approve

# Wait for the resources to be created
echo "Waiting for resources to be created..."
sleep 30  # Wait for 30 seconds to allow resources to be created

# Verifying that resources have been created
echo "Verifying created resources:"

# Check S3 bucket
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
if aws s3 ls "s3://$S3_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'
then
    echo "S3 bucket $S3_BUCKET_NAME does not exist"
else
    echo "S3 bucket $S3_BUCKET_NAME exists"
fi

# Check DynamoDB table
DYNAMODB_TABLE_NAME=$(terraform output -raw dynamodb_table_name)
if aws dynamodb describe-table --table-name $DYNAMODB_TABLE_NAME 2>&1 | grep -q 'ResourceNotFoundException'
then
    echo "DynamoDB table $DYNAMODB_TABLE_NAME does not exist"
else
    echo "DynamoDB table $DYNAMODB_TABLE_NAME exists"
fi

# Check Lambda function
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name)
if aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME 2>&1 | grep -q 'ResourceNotFoundException'
then
    echo "Lambda function $LAMBDA_FUNCTION_NAME does not exist"
else
    echo "Lambda function $LAMBDA_FUNCTION_NAME exists"
fi

# Check API Gateway
API_GATEWAY_NAME=$(terraform output -raw api_gateway_name)
if aws apigateway get-rest-apis | grep -q "$API_GATEWAY_NAME"
then
    echo "API Gateway $API_GATEWAY_NAME exists"
else
    echo "API Gateway $API_GATEWAY_NAME does not exist"
fi

# Check CloudFront distribution
CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
if aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID 2>&1 | grep -q 'NoSuchDistribution'
then
    echo "CloudFront distribution $CLOUDFRONT_DISTRIBUTION_ID does not exist"
else
    echo "CloudFront distribution $CLOUDFRONT_DISTRIBUTION_ID exists"
fi

echo "Resource verification completed."

cd ../

echo "======================================================================================================"
echo "Installing Docker ..."
# Install Docker
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo docker run hello-world
sudo systemctl enable docker
docker --version
sudo usermod -a -G docker $(whoami)
newgrp docker

echo "======================================================================================================"
echo "Installing eksctl and kubectl ..."
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo cp /tmp/eksctl /usr/bin
eksctl version

# Install kubectl
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
kubectl version --short --client

echo "======================================================================================================"
echo "Creating EKS Cluster..."
# Creating EKS Cluster
eksctl create cluster \
  --name cloudmart \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 1 \
  --with-oidc \
  --managed

echo "======================================================================================================"
echo "Updating Kubernetes config ..."
# update the kubectl configuration.
aws eks update-kubeconfig --name cloudmart

# Verifying cluster connectivity
kubectl get svc
kubectl get nodes

echo "======================================================================================================"
echo "Creating Service Account and Role for Kubernetes cluster ...."
eksctl create iamserviceaccount \
  --cluster=cloudmart \
  --name=cloudmart-pod-execution-role \
  --role-name CloudMartPodExecutionRole \
  --attach-policy-arn=arn:aws:iam::aws:policy/AdministratorAccess\
  --region us-east-1 \
  --approve

echo "Cluster creation completed."
echo "======================================================================================================"
echo "Setup complete....."

