# AWS IAM Policies for Minecraft Infrastructure

This document outlines the **Minimum Privilege** IAM policies required for your EC2 instance to manage its own automation (Security Groups, IP detection) and the privacy/security considerations of the current architecture.

## 1. Instance Profile Policy

Attach a role with this policy to your Minecraft EC2 instance. This allows the `proxy-helper.js` script to:
1.  **Describe Instances**: To find its own Security Group ID.
2.  **Authorize Security Group Ingress**: To open ports for players (only for Geyser/UDP potentially).
3.  **Revoke Security Group Ingress**: To close ports when a server is deleted.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/Application": "MinecraftProxy" 
                }
            }
        }
    ]
}
```
> **Note**: Ideally, tag your Security Group with `Application=MinecraftProxy` and use the condition above to restrict the script from modifying other security groups. If you cannot tag, remove the `Condition` block (less secure).

## 2. Infrastructure Security Architecture

### Localhost Binding
All backend Minecraft servers (Fabric, Forge, etc.) are configured to bind to `127.0.0.1` (`server-ip` in `server.properties`).
*   **Effect**: They are **NOT** accessible from the internet directly via TCP.
*   **Flow**: Internet -> Proxy (Port 25599) -> Localhost (Backend Port).
*   **Benefit**: You do not need to open hundreds of TCP ports in your firewall. Only the Proxy port needs to be open.

### UDP / Bedrock (Geyser)
Bedrock Edition uses UDP, which the current TCP Proxy implementation handles via a `udp-proxy.js` wrapper or direct tunnel. 
*   **Current Script Logic**: If Geyser is enabled, the script **opens the specific UDP port** in the Security Group.
*   **Why**: UDP packets are connectionless and sensitive to latency; direct routing (or a lightweight UDP forwarder) is preferred over complex tunneling sometimes.
*   **Cleanup**: When you delete a server, the script calls `RevokeSecurityGroupIngress` to close this UDP port.

## 3. Privacy & Compliance

*   **Logs**: Server logs (`logs/latest.log`) contain player IP addresses. Ensure you rotate these logs or delete them if strict privacy is required.
*   **Backups**: If you automate backups to S3, ensure the S3 bucket is private and encrypted (`AES-256` or `KMS`).
*   **Access**: Only the `mc-manager.sh` script (running as the `minecraft` user) and `root` have access to the server files/properties.

## 4. Recommended Security Group Rules (Inbound)

| Protocol | Port | Source | Description |
| :--- | :--- | :--- | :--- |
| TCP | 22 | Your IP | SSH Access (Management) |
| TCP | 25599 | 0.0.0.0/0 | **Proxy Main Port** (Players connect here) |
| UDP | 25565+ | 0.0.0.0/0 | Dynamic ports for Geyser (Opened automatically) |

**All other ports should be closed by default.**
