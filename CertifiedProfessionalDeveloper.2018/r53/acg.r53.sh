#!/bin/bash 

### Implement the acloud.guru Route53 Lab steps as bash.
# This script is not idempotent. It assume that none of thise resources exists in the default vpc. It does try and clean up after itself.
# It is also not intended to be run as a command. The intent is to run each section or snippet in conjunction with the appropriate section of the
# lab. However, it should run attended but this hasn't been tested.



domainName="anothercloudguruwebsite.com" # Must be an available domain name

firstName="john"
lastName="miller"
contactType="PERSONAL"
addressLine1="26928 Marbella"
addressLine2=""
city="mission viejo"
state="ca"
countryCode="1"
zipCode="92691"
phoneNumber="9496895051"
email="jmiller@pdata.com"
fax=""

contact="FirstName=$firstName,LastName=$lastName,ContactType=$contactType,AddressLine1=$addressLine1,AddressLine2=$addressLine2,City=$city,State=$state,CountryCode=$countryCode,ZipCode=$zipCode,PhoneNumber=$phoneNumber,Email=$email,Fax=$fax"

## Register the domain (Fails and I don't know why!?!)
operationId=$(aws route54domains register-domain --domain-name $domainName --duration-in-years 1 --no-auto-renew --admin-contact $contact --registrant-contact $contact --tech-contact $contact --privacy-protect-admin-contact --privacy-protect-registrant-contact --privacy-protect-tech-contact)

# Post domain registration

hostedZoneId=$(aws route53 list-hosted-zones-by-name --dns-name $domainName | jq -r ".HostedZones[].Id")
hostedZoneId=${hostedZoneId##/*/}
echo $hostedZoneId

canonicalHostedZoneId=$(aws elbv2 describe-load-balancers --load-balancer-arns $loadBalancerArn | jq -r ".LoadBalancers[].CanonicalHostedZoneId")
echo $canonicalHostedZoneId

# Create apex record

changeBatch=$( cat <<EOF
{
  "Comment": "Apex record set",
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "$domainName",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$canonicalHostedZoneId",
          "DNSName": "$loadBalancerDns",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF
) 

echo "$changeBatch"

changeInfoId=$aws route53 change-resource-record-sets --hosted-zone-id $hostedZoneId --change-batch "$changeBatch"  | jq -r ".ChangeInfo.Id")
echo$ changeInfoId
changeInfoId=${changeInfoId##/*/}

aws route53 get-change --id $changeInfoId 

# This could take a while to propogate to your DNS. You can test it right away in the console.
curl $domainName
