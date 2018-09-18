#!/bin/bash 

### Implement the acloud.guru CLI Lab steps as bash.

# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

# Bucket names must be globally unique, change accordingly
bucketName='acloudguru1234-jmm'

# Create User Developer 1, programmatic access
aws iam create-user --user-name Developer1

# Create Group Developers, Administrator Access
groupArn=$(aws iam create-group --group-name Developers | jq -r ".Group.Arn")
aws iam attach-group-policy --group-name Developers --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam list-attached-group-policies --group-name Developers

# Add Developer 1 to Developers group
aws iam add-user-to-group --group-name Developers --user-name Developer1

# Get access key id and secret access key
accessKey=$(aws iam create-access-key --user-name Developer1 | jq -r ".AccessKey")
accessKeyId=$(echo $accessKey | jq -r ".AccessKeyId")
secretAccessKey=$(echo $accessKey | jq -r ".SecretAccessKey")
aws iam list-access-keys --user-name Developer1

# Configure CLI to use access key, use a aws profile to preserve the default configuration
aws configure set region us-east-1 --profile acg
aws configure set aws_access_key_id $accessKeyId --profile acg
aws configure set aws_secret_access_key $secretAccessKey --profile acg
aws configure list --profile acg

# Make bucket 
aws s3 mb "s3://$bucketName" --profile acg

# Write hello cloud gurus to hello.txt
echo "hello cloud gurus" > hello.txt

# Copy hello.txt to s3 bucket
aws s3 cp hello.txt "s3://$bucketName" --profile acg
aws s3 ls "s3://$bucketName" --profile acg

# Delete Devloper1's access key
aws iam delete-access-key --user-name Developer1 --access-key-id $accessKeyId
aws iam list-access-keys --user-name Developer1

# Create new access key
accessKey=$(aws iam create-access-key --user-name Developer1 | jq -r ".AccessKey")
accessKeyId=$(echo $accessKey | jq -r ".AccessKeyId")
secretAccessKey=$(echo $accessKey | jq -r ".SecretAccessKey")
aws iam list-access-keys --user-name Developer1

# Access S3 bucket showing error:
# An error occurred (InvalidAccessKeyId) when calling the ListObjects operation: The AWS Access Key Id you provided does not exist in our records.
aws s3 ls "s3://$bucketName" --profile acg

# Configure CLI to use access key
aws configure set region us-east-1 --profile acg
aws configure set aws_access_key_id $accessKeyId --profile acg
aws configure set aws_secret_access_key $secretAccessKey --profile acg
aws configure list --profile acg

# Access s3 bucket and show success
aws s3 ls "s3://$bucketName" --profile acg

# Clean up
aws iam remove-user-from-group --user-name Developer1 --group-name Developers
aws iam delete-access-key --user-name Developer1 --access-key-id $accessKeyId
aws iam delete-user --user-name Developer1
aws iam detach-group-policy --group-name Developers --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-group --group-name Developers
aws s3 rb "s3://$bucketName" --force
aws configure set region "" --profile acg
aws configure set aws_access_key_id "" --profile acg
aws configure set aws_secret_access_key "" --profile acg
