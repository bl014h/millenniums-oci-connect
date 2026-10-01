# MILLENNIUMS.AI — Oracle Cloud read-only scan access

The Oracle Resource Manager stack behind the **Connect Oracle Cloud** button in the MILLENNIUMS.AI console.

It creates, in your tenancy's home region:

- a group `MillenniumsCloudScan` and a user `millenniums-cloud-scan` (API key only — no console password),
- a policy with four read-only statements (see `main.tf`) — never object contents, database wallets or VM console output,
- an API key holding your workspace's **public** key. The private half never leaves MILLENNIUMS.AI.

It then reports the new user's OCID back to your workspace, so there is nothing to copy by hand.

Revoke access at any time by destroying the stack, or by deleting the API key from that user.

Use the button in the console rather than this repo directly: it fills in your workspace's key and callback.
