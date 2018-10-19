#!/bin/bash 

### AWS CLI code for the RDS db encryption, multi-AZ and read
### replica labs from the acloud.guru AWS Certified Develper
### Associate course 

# turn off history expansion
set +H

# Go home
region="us-east-1"
aws configure set default.region $region

# Create an RDS Instance, modify the instance to enable multiple
# AZs, create a new instance from the the first, with encryprion
# enabled.

# Initial db instance
dbInstanceId='acloudguru-db-instance'

# Launch initial db instance
dbInstance=$(aws rds create-db-instance \
  --db-name acloudguru_db \
  --db-instance-identifier $dbInstanceId \
  --allocated-storage 20 \
  --db-instance-class db.t2.small \
  --engine mysql \
  --master-username acloudguru \
  --master-user-password acloudguru \
  --license-model general-public-license \
  --engine-version 5.7 \
  --db-parameter-group-name default.mysql5.7 \
  --option-group-name default:mysql-5-7 \
  --vpc-security-group-ids $rdsSecurityGroupId \
  --tags Key=org,Value=acg \
  --copy-tags-to-snapshot
)

# Wait for aws to create the rds instance
aws rds wait db-instance-available \
  --db-instance-identifier $dbInstanceId 

# The endpoint and port are needed to configure the db connection
# on the web instance 
dbEndpoint=$(aws rds describe-db-instances \
  | jq -r '.DBInstances[].Endpoint.Address')
dbPort=$(aws rds describe-db-instances \
  | jq -r '.DBInstances[].Endpoint.Port')
echo $dbEndpoint $dbPort

# Turn on multi-az
aws rds modify-db-instance \
  --db-instance-identifier $dbInstanceId \
  --multi-az \
  --apply-immediately
aws rds wait db-instance-available \
  --db-instance-identifier $dbInstanceId

# Create the encrypted instance from a snapshot of the first
# instance.

dbSourceSnapshotId='acloudguru-manual-snap'

# Create a snapshot
aws rds create-db-snapshot \
  --db-snapshot-identifier $dbSourceSnapshotId \
  --db-instance-identifier $dbInstanceId
aws rds wait db-snapshot-available \
  --db-snapshot-identifier $dbSourceSnapshotId 

# Create encryption key
kmsKeyId=$( aws kms create-key \
  --description 'acloud.guru rds encryption key' \
  --tags TagKey=org,TagValue=acg \
  | jq -r ".KeyMetadata.Arn" )

# Copy the snapshot and encrypt the data with the key

dbTargetSnapshotId='acloudguru-manual-snap-encrypted'

# Copy snapshot with encryption
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier $dbSourceSnapshotId \
  --target-db-snapshot-identifier $dbTargetSnapshotId \
  --kms-key-id $kmsKeyId \
  --copy-tags
aws rds wait db-snapshot-available \
  --db-snapshot-identifier $dbTargetSnapshotId 

# Launch a new db instance from the encrypted snapshot
dbEncryptedInstanceId='acloudguru-db-encrypted-instance'

# Restore the encrypted snapshot to a new db instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $dbEncryptedInstanceId \
  --db-snapshot-identifier $dbTargetSnapshotId
aws rds wait db-instance-available \
  --db-instance-identifier $dbEncryptedInstanceId 

# Check our math

# Should contain the arn for the kms key
dbKmsKeyId=$(aws rds describe-db-instances \
  --db-instance-identifier $dbEncryptedInstanceId \
  | jq -r ".DBInstances[].KmsKeyId")

echo $kmsKeyId
echo $dbKmsKeyId
echo 'These should be the same'

if [ $kmsKeyId = $dbKmsKeyId ]
then
  echo 'Saul Goodman!'
fi

dbReplicaInstanceId='acloudguru-db-replica-instance'

echo $dbReplicaInstanceId $dbInstanceId 

# Create a read replica for the encrypted db
readReplica=$( aws rds create-db-instance-read-replica \
  --db-instance-identifier $dbReplicaInstanceId \
  --source-db-instance-identifier $dbEncryptedInstanceId \
  --no-publicly-accessible \
  --copy-tags-to-snapshot 
)
aws rds wait db-instance-available \
  --db-instance-identifier $dbReplicaInstanceId

dbKmsKeyId=$(echo "$readReplica" | jq -r ".DBInstance.KmsKeyId")

echo $kmsKeyId
echo $dbKmsKeyId
echo 'These should be the same'

if [ $kmsKeyId = $dbKmsKeyId ]
then
  echo 'Saul Goodman!'
fi

# Teardown

# Delete source snapshot
aws rds delete-db-snapshot \
  --db-snapshot-identifier $dbSourceSnapshotId 
aws rds wait db-snapshot-deleted \
  --db-snapshot-identifier $dbSourceSnapshotId 

# Delete target snapshot
aws rds delete-db-snapshot \
  --db-snapshot-identifier $dbTargetSnapshotId
aws rds wait db-snapshot-deleted \
  --db-snapshot-identifier $dbTargetSnapshotId

# Delete encrypted instance
aws rds delete-db-instance \
  --db-instance-identifier $dbReplicaInstanceId \
  --skip-final-snapshot
aws rds wait db-instance-deleted \
  --db-instance-identifier $dbReplicaInstanceId

# Delete encrypted instance
aws rds delete-db-instance \
  --db-instance-identifier $dbEncryptedInstanceId \
  --skip-final-snapshot
aws rds wait db-instance-deleted \
  --db-instance-identifier $dbEncryptedInstanceId

# Delete unencrypted instance
aws rds delete-db-instance \
  --db-instance-identifier $dbInstanceId \
  --skip-final-snapshot
aws rds wait db-instance-deleted \
  --db-instance-identifier $dbInstanceId

# Delete KMS Key
aws kms schedule-key-deletion \
  --key-id $kmsKeyId \
  --pending-window-in-days 7

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
