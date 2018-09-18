#!/bin/bash 

### Implement the acloud.guru EC2 with S3 Lab steps as bash.

# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

# Bucket names must be globally unique, change accordingly
bucketName='acloudguru1234-jmm'

# Create Role
  # EC2
  # AmazonS3FullAccess
  # MyS3AdminAccess
  # Allows EC2 instances to call AWS S3 on your behalf.

# Show that S3 cannot be accessed from instance
  # SSH into EC2 Instance
  # aws s3 ls

# Apply Role to EC2 Instance
  # Attach IAM Role AmazonS3FullAccess

# Show access to S3
  # SSH into EC2 Instance
  # aws s3 ls
  # echo "Hello Cloud Gurus 2" > hello2.txt
  # aws s3 cp hello2.txt $bucketName
  # aws s3 ls



# Clean up
