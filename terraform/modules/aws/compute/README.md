# AWS Compute Module

This module provisions an EC2 instance with associated networking and storage.

## Features
- Provisions an EC2 instance (Amazon Linux 2023 by default).
- Creates/Manages Security Groups for SSH and Egress (optional).
- Supports attaching existing Key Pairs or generating new ones (via helper modules).

## Usage

```hcl
module "server" {
  source = "./modules/aws/compute"

  name     = "my-server"
  key_name = "my-key"
}
```

## Architecture Decisions

### Security Groups: Embedded vs. Separated
Currently, Security Groups are **embedded** within this compute module by default.

**Rationale (Best Practices & Industry Standards):**

We have chosen this "Dedicated Security Group" pattern intentionally. This decision balances "Principles of Least Privilege" against "Cognitive Overhead".

**Why Embedded? (Pros)**
1.  **Principle of Least Privilege (Security):** Every instance gets a dedicated firewall rule set tailored exactly to its needs. This isolates the blast radius; compromising one instance's SG rules doesn't accidentally open ports on shared infrastructure.
2.  **Lifecycle Coupling:** The security rules live and die with the instance. There are no "orphan" security groups cluttering the VPC after the instance is destroyed.
3.  **Naming Clarity:** Resources are named deterministically based on the instance name (e.g., `<name>-ssh-only`), making audit trails obvious.
4.  **Simplicity:** Creates a "Batteries Included" experience. The module works out-of-the-box without requiring complex network wiring.

**Why Not a Separate Module?**
Separating `security-groups` into their own module right now would be a **Premature Optimization**.
*   It would add **Cognitive Overhead** (file sprawl, more variable passing) without immediate benefit for our current independent-node architecture.
*   If we move to public modules (like `terraform-aws-modules`) in the future, we will adopt their patterns then.

**Future Evolution (When to Separate):**
We should refactor SGs into a separate module or root configuration only if:
*   **M:N Reuse:** We need to share the exact same SG across many disparate deployments (e.g., a shared "Corporate VPN Access" SG).
*   **Cyclic Dependencies:** We have a multi-tier application (Web -> App -> DB) where SGs need to reference each other's IDs cyclically before instances exist.

**Usage:**
*   **Default:** `create_default_sgs = true` (Module manages the lifecycle).
*   **Hybrid:** `vpc_security_group_ids = ["sg-123"]` (Attach extra shared groups).
*   **Fully Managed External:** `create_default_sgs = false` + `vpc_security_group_ids = [...]` (Disable internal logic entirely).

*Note: If you move SGs to their own module or manage them externally later, using `terraform state mv` may be required to prevent recreation if you want to strictly "move" the existing SG resource.*

### SSH Keys
See [key-pair module's README](../key-pair/README.md) for details on the Key Pair decoupling strategy.
