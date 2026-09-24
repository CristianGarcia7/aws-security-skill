# Network and Ports

## Security groups default-deny

A security group should start with no inbound rules and gain only what the
workload actually needs. Never attach a security group that already carries
a broad "standard access" or "restricted access" rule set copied from
another project without reviewing every line — inherited rules are a common
source of forgotten exposure.

## Allowed vs. forbidden

| Port / service | World-open (`0.0.0.0/0`, `::/0`) | Correct exposure |
|---|---|---|
| 80, 443 (HTTP/HTTPS) | Only on a load balancer or CloudFront distribution | Never directly on an instance's own SG unless that instance *is* the LB |
| 22 (SSH) | Never | No inbound rule at all — use SSM Session Manager |
| 3389 (RDP) | Never | Same — SSM, or a bastion with just-in-time access |
| 3306 (MySQL), 5432 (PostgreSQL) | Never | SG rule referencing the application's SG as source, not a CIDR |
| 6379 (Redis), 27017 (MongoDB) | Never | Same — SG-to-SG reference, private subnet only |
| 21 / 20 (FTP, FTP passive range) | Never | Avoid FTP entirely; use SFTP over SSM-tunneled access or a managed transfer service if unavoidable |
| Any admin panel (control panel UI, database admin UI) | Never | SSM port forwarding, VPN, or an authenticated reverse proxy — never a public listener |

A security group rule with no description is a rule nobody can audit six
months later — every rule should state who/what it is for and, for a
temporary grant, when it should be revoked.

## SSM Session Manager instead of SSH

SSM Session Manager gives shell access without an open inbound port, without
a bastion host, and with every session logged centrally. It requires the
SSM agent (present by default on most current AMIs) and a role with
`AmazonSSMManagedInstanceCore` attached — no security group change needed on
the target.

```
aws ssm start-session --target <INSTANCE_ID>
```

If SSH is still required for a specific tool that cannot use SSM (rare),
scope the rule to a single `/32` for a limited time and record an explicit
revoke step — see `hestia-port-access` for a full temporary-access grant
pattern with automatic-adjacent tooling, when installed.

## Databases in private subnets

- `PubliclyAccessible=false` on every RDS instance/cluster — a database
  should never have a public IP.
- Place the database in a private subnet (no route to an internet gateway).
- Access it only from application security groups via an SG-to-SG reference,
  not a CIDR block — this way the rule stays correct even as the
  application's IPs change.

## Audit commands (read-only)

Find security groups with a world-open rule on a port that should never be
world-open:

```
aws ec2 describe-security-groups \
  --query "SecurityGroups[].IpPermissions[?(IpRanges[?CidrIp=='0.0.0.0/0'] || Ipv6Ranges[?CidrIpv6=='::/0']) && (FromPort==\`22\` || FromPort==\`3389\` || FromPort==\`3306\` || FromPort==\`5432\` || FromPort==\`6379\` || FromPort==\`27017\` || FromPort==\`21\`)]"
```

Find publicly accessible RDS instances:

```
aws rds describe-db-instances \
  --query "DBInstances[?PubliclyAccessible==\`true\`].[DBInstanceIdentifier,PubliclyAccessible]" \
  --output table
```

Find instances with IMDSv2 not required:

```
aws ec2 describe-instances \
  --query "Reservations[].Instances[?MetadataOptions.HttpTokens!='required'].[InstanceId,MetadataOptions.HttpTokens]" \
  --output table
```

`assets/audit-aws-exposure.sh` wraps these checks (plus S3 and stale-key
checks) into one read-only script.

## Quick checklist

- [ ] Only 80/443 world-open, and only on a load balancer/CloudFront.
- [ ] No SG allows 22, 3389, 3306, 5432, 6379, 27017, 21, or an admin panel
      from `0.0.0.0/0` or `::/0`.
- [ ] SSH access, if any, is temporary, `/32`-scoped, and has a recorded
      revoke.
- [ ] SSM Session Manager is the default shell-access path.
- [ ] Every RDS instance has `PubliclyAccessible=false` and lives in a
      private subnet.
- [ ] Every SG rule has a description.
