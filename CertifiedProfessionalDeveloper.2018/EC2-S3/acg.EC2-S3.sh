#!/bin/bash 

### Implement the acloud.guru EC2 with S3 Lab steps as bash.

# This script is not idempotent. It assume that none of these resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.
# This script assumes that none of the requisite AWS resources exist. To use existing resources assign the AWS resources identifiers to the appropriate vars

# Bucket names must be globally unique, change accordingly
bucketName='acloudguru1234-jmm'

# The ARN of the desired policy
s3FullAccessArn=arn:aws:iam::aws:policy/AmazonS3FullAccess

## Create Role
# This Lab has a hard dependency on the EC2 instance created in the EC2101 lab: 
#   https://gist.github.com/JohnMichaelMiller/fe2c0a4d743f6f6c02fe6a5b28169b54
echo $publicDNS $instanceId

# AmazonS3FullAccess Policy
ec2AssumeRolePolicy=$( cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
) 

testScript=$( cat <<EOF
aws s3 ls
echo "Hello Cloud Gurus 2" > hello2.txt
aws s3 mb s3://$bucketName
aws s3 cp hello2.txt s3://$bucketName
aws s3 ls s3://$bucketName
EOF
) 


# MyS3AdminAccess Role
aws iam create-role --role-name MyS3AdminAccess --assume-role-policy-document "$ec2AssumeRolePolicy"

# Show that S3 cannot be accessed from instance
  # SSH into EC2 Instance
ssh -i "~/.ssh/$keyName.pem" "ec2-user@$publicDNS"
aws s3 ls # Expected Error: Unable to locate credentials. You can configure credentials by running "aws configure".
exit

# Apply Role to EC2 Instance
  # Attach IAM Role MyS3AdminAccess
# Attach policy to role
aws iam attach-role-policy --role-name MyS3AdminAccess --policy-arn $s3FullAccessArn
# Create an instance profile
aws iam create-instance-profile --instance-profile-name MyS3AdminAccess-Instance-Profile
# Add the role to the instance profile
aws iam add-role-to-instance-profile --role-name MyS3AdminAccess --instance-profile-name MyS3AdminAccess-Instance-Profile
# Associate the iam instance profile with the instance
iip=$(aws ec2 associate-iam-instance-profile --instance-id $instanceId --iam-instance-profile Name=MyS3AdminAccess-Instance-Profile | jq -r ".IamInstanceProfileAssociation.AssociationId")
aws ec2 describe-iam-instance-profile-associations

# Show access to S3
  # SSH into EC2 Instance
ssh -i "~/.ssh/$keyName.pem" "ec2-user@$publicDNS"  "$testScript"

# Teardown
# aws ec2 associate-iam-instance-profile
aws ec2 disassociate-iam-instance-profile --association-id $iip
# aws iam add-role-to-instance-profile
aws iam remove-role-from-instance-profile --role-name MyS3AdminAccess --instance-profile-name MyS3AdminAccess-Instance-Profile
# aws iam create-instance-profile
aws iam delete-instance-profile --instance-profile-name MyS3AdminAccess-Instance-Profile
# aws iam attach-role-policy
aws iam detach-role-policy --role-name MyS3AdminAccess --policy-arn $s3FullAccessArn
# aws iam create-role
aws iam delete-role --role-name MyS3AdminAccess

# Include cleanup from the EC2-101 lab: 
#   https://gist.github.com/JohnMichaelMiller/fe2c0a4d743f6f6c02fe6a5b28169b54

#See: https://aws.amazon.com/blogs/security/new-attach-an-aws-iam-role-to-an-existing-amazon-ec2-instance-by-using-the-aws-cli/
