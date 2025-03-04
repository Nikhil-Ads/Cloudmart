#!/bin/bash

# Delete the Kubernetes resources
kubectl delete service cloudmart-frontend-app-service
kubectl delete deployment cloudmart-frontend-app
kubectl delete service cloudmart-backend-app-service
kubectl delete deployment cloudmart-backend-app

# Delete the EKS cluster
eksctl delete cluster --name cloudmart --region us-east-1

# Destroy resources created by terraform
cd terraform/
terraform destroy -auto-approve