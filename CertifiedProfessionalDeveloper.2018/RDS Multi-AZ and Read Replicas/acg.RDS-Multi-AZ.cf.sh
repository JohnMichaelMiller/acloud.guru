#!/bin/bash 

### AWS CLI code and Cloudformation template for the RDS
### multi-AZ, data encryption, and read replica labs from
### the acloud.guru AWS Certified Develper Associate course 

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

bucketName='acloudguru1234-jmm' # Bucket names must be globally unique, change accordingly
stackName="acg-rds-multi-az"
dbInstanceType='db.t2.small'
keyAdminArn='arn:aws:iam::014959391663:user/jmiller' # Intentionally incorrect

# The CloudFormation template to create the security group and the instance
cat > temp.cf.yaml <<EOF
---
### AWS CloudFormation template for the RDS multi-AZ, data
### encryption, and read replica labs from the acloud.guru
### AWS Certified Develper Associate course 
AWSTemplateFormatVersion: 2010-09-09
Description: acloud.guru RDS Multi-AZ and Read Replica Lab
Parameters:      # Default values for template parameters are useful when testing templates in the AWS Web Console
  dbInstanceType:
    Type: String
    Default: db.t2.small
  keyAdminArn:
    Description: >-
      ARN of the key administrator
    Type: String
    Default: arn:aws:iam::014959391663:root # Intentionally incorrect
Resources:
  rdsKeyAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub alias/\${AWS::StackName}-acg-rds-key
      TargetKeyId: !Ref rdsKey
  rdsKey:
    Properties:
      Description: Created by the data encryption portion of the RDS multi-AZ and read replica labs
      Enabled: true
      EnableKeyRotation: false
      KeyPolicy: 
        Version: "2012-10-17"
        Id: "acg-key-default-1"
        Statement: 
          - 
            Sid: "Allow administration of the key"
            Effect: "Allow"
            Principal: 
              AWS:
              - !Ref keyAdminArn
            Action: 
              - "kms:Create*"
              - "kms:Describe*"
              - "kms:Enable*"
              - "kms:List*"
              - "kms:Put*"
              - "kms:Update*"
              - "kms:Revoke*"
              - "kms:Disable*"
              - "kms:Get*"
              - "kms:Delete*"
              - "kms:ScheduleKeyDeletion"
              - "kms:CancelKeyDeletion"
            Resource: "*"
          - 
            Sid: "Allow use of the key"
            Effect: "Allow"
            Principal: 
              AWS:
              - !Ref keyAdminArn
            Action: 
              - "kms:Encrypt"
              - "kms:Decrypt"
              - "kms:ReEncrypt*"
              - "kms:GenerateDataKey*"
              - "kms:DescribeKey"
            Resource: "*"
      Tags:
        - Key: Name
          Value: rdsInstance
        - Key: Lab
          Value: acloud.guru.rds.multi-az
    Type: AWS::KMS::Key
  rdsInstance:
    Properties:
      AllocatedStorage: '20'
      AutoMinorVersionUpgrade: true
      CopyTagsToSnapshot: true
      DBInstanceClass: !Ref dbInstanceType
      DBInstanceIdentifier: 
        !Sub \${AWS::StackName}-acg-rds-instance
      DBName: acloudguru_db
      Engine: mysql 
      MasterUsername: acloudguru
      MasterUserPassword: acloudguru # Obviously a bad idea. The parameter store is a better idea.
      KmsKeyId: !Ref rdsKey # Encryption key
      MultiAZ: true # Highly available
      Port: '3306'
      StorageEncrypted: true # Encrypt the data
      Tags:
        - Key: Name
          Value: rdsInstance
        - Key: Lab
          Value: acloud.guru.rds.multi-az
    Type: AWS::RDS::DBInstance
  rdsReadReplicaInstance:
    Properties:
      DBInstanceClass: !Ref dbInstanceType
      AllocatedStorage: '20'
      CopyTagsToSnapshot: true
      DBInstanceIdentifier: 
        !Sub ${AWS::StackName}-acg-read-replica-rds-instance
      SourceDBInstanceIdentifier: !Ref rdsInstance
    Type: AWS::RDS::DBInstance
EOF

aws s3 cp temp.cf.yaml "s3://$bucketName"
url=$(aws s3 presign "s3://$bucketName/temp.cf.yaml")

# Validate that the template is well formed
aws cloudformation validate-template \
  --template-url $url

# Build the template parameter list
templateParameters="ParameterKey=dbInstanceType,ParameterValue=$dbInstanceType "\
"ParameterKey=keyAdminArn,ParameterValue=$keyAdminArn "

echo "$templateParameters"

# Create the stack
aws cloudformation create-stack \
  --stack-name $stackName \
  --template-url $url \
  --parameters $templateParameters \
  --disable-rollback \
  --capabilities CAPABILITY_IAM \
  --tags Key=group,Value=acloud.guru

aws cloudformation wait stack-create-complete \
  --stack-name $stackName

# aws cloudformation update-stack --stack-name $stackName --template-url $url --parameters $templateParameters --capabilities CAPABILITY_IAM --tags Key=group,Value=acloud.guru

# Monitor the stack creation status
aws cloudformation describe-stacks \
  | jq -r ".Stacks[].StackStatus"


## Cleanup

rm temp.cf.yaml

# Delete the stack
aws cloudformation delete-stack --stack-name $stackName
aws cloudformation wait stack-delete-complete \
  --stack-name $stackName

# This code is not idempotent. It assumes that none of these
# resources exists in the default vpc. It does try and clean up
# after itself. It is also not intended to be run as a command.
# The intent is to run each section or snippet in conjunction
# with the appropriate section of the lab. However, it should
# run attended but this hasn't been tested. This script assumes
# that none of the requisite AWS resources exist. To use existing
# resources assign the AWS resources identifiers to the appropriate
# vars and comment out the related code.

# MIT License

# Copyright (c) 2018 John Michael Miller

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
