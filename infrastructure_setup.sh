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


cd ../

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
echo "Installing Docker ..."
# Install Docker
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
echo "Checking docker installation"
if command -v docker &> /dev/null; then
    echo "Docker Version: $(docker --version)"
    echo "======================================================================================================"
    echo "Setup complete....."
    sudo usermod -a -G docker $(whoami)
    newgrp docker;
else
    echo "Docker installation not found. Please install docker."
    exit 1
fi
