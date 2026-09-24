#!/usr/bin/env bash
# audit-aws-exposure.sh — read-only AWS account audit against the hard rules
# in SKILL.md. Never mutates anything: every call below is a describe/get/
# list operation. Requires the AWS CLI v2 and jq.
#
# Usage:
#   ./audit-aws-exposure.sh --profile <PROFILE> --region <REGION> [--key-age-days N]
#
# Exit code is 0 if no findings, 2 if any finding was reported, 1 on a
# usage/tooling error.

set -euo pipefail

PROFILE=""
REGION=""
KEY_AGE_DAYS=90

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --key-age-days) KEY_AGE_DAYS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PROFILE" ] || [ -z "$REGION" ]; then
  echo "usage: $0 --profile <PROFILE> --region <REGION> [--key-age-days N]" >&2
  exit 1
fi

command -v aws >/dev/null 2>&1 || { echo "error: aws CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 1; }

AWS=(aws --profile "$PROFILE" --region "$REGION")
finding_count=0

report() {
  finding_count=$((finding_count + 1))
  echo "[$1] $2"
}

echo "== Security groups: world-open on a non-80/443 port =="
sg_json="$("${AWS[@]}" ec2 describe-security-groups --output json)"
while read -r line; do
  [ -n "$line" ] && report "NETWORK" "world-open security group rule: $line"
done < <(echo "$sg_json" | jq -r '
  .SecurityGroups[]
  | . as $sg
  | .IpPermissions[]
  | select((.FromPort // -1) != 80 and (.FromPort // -1) != 443)
  | select(
      (.IpRanges[]?.CidrIp // "" ) == "0.0.0.0/0"
      or (.Ipv6Ranges[]?.CidrIpv6 // "") == "::/0"
    )
  | "\($sg.GroupId) \($sg.GroupName) port=\(.FromPort // "all")-\(.ToPort // "all")"
')

echo
echo "== RDS instances: PubliclyAccessible=true =="
while read -r id; do
  [ -n "$id" ] && report "DATABASE" "publicly accessible RDS instance: $id"
done < <("${AWS[@]}" rds describe-db-instances --output json 2>/dev/null | jq -r '
  .DBInstances[] | select(.PubliclyAccessible == true) | .DBInstanceIdentifier
')

echo
echo "== S3 buckets: Block Public Access not fully enabled =="
buckets="$("${AWS[@]}" s3api list-buckets --output json | jq -r '.Buckets[].Name')"
for bucket in $buckets; do
  cfg="$("${AWS[@]}" s3api get-public-access-block --bucket "$bucket" --output json 2>/dev/null || echo '{}')"
  all_on="$(echo "$cfg" | jq -r '
    (.PublicAccessBlockConfiguration.BlockPublicAcls // false)
    and (.PublicAccessBlockConfiguration.IgnorePublicAcls // false)
    and (.PublicAccessBlockConfiguration.BlockPublicPolicy // false)
    and (.PublicAccessBlockConfiguration.RestrictPublicBuckets // false)
  ')"
  if [ "$all_on" != "true" ]; then
    report "S3" "bucket without full Block Public Access: $bucket"
  fi
done

echo
echo "== EC2 instances: IMDSv2 not required =="
while read -r id; do
  [ -n "$id" ] && report "IMDS" "instance without IMDSv2 required: $id"
done < <("${AWS[@]}" ec2 describe-instances --output json | jq -r '
  .Reservations[].Instances[]
  | select(.MetadataOptions.HttpTokens != "required")
  | .InstanceId
')

echo
echo "== IAM users: active access keys older than ${KEY_AGE_DAYS} days =="
now_epoch="$(date -u +%s)"
users="$("${AWS[@]}" iam list-users --output json | jq -r '.Users[].UserName')"
for user in $users; do
  while IFS=$'\t' read -r key_id create_date; do
    [ -z "$key_id" ] && continue
    created_epoch="$(date -u -d "$create_date" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%S' "${create_date%%+*}" +%s 2>/dev/null || echo 0)"
    [ "$created_epoch" -eq 0 ] && continue
    age_days=$(( (now_epoch - created_epoch) / 86400 ))
    if [ "$age_days" -gt "$KEY_AGE_DAYS" ]; then
      report "IAM" "user '$user' has active access key ${key_id:0:8}... aged ${age_days}d (> ${KEY_AGE_DAYS}d)"
    fi
  done < <("${AWS[@]}" iam list-access-keys --user-name "$user" --output json | jq -r '
    .AccessKeyMetadata[] | select(.Status == "Active") | [.AccessKeyId, .CreateDate] | @tsv
  ')
done

echo
echo "----------------------------------------"
if [ "$finding_count" -eq 0 ]; then
  echo "No findings."
  exit 0
else
  echo "Findings: $finding_count"
  exit 2
fi
