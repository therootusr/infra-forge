# AWS Key Pair Module

This module handles the generation and management of SSH Key Pairs for AWS instances.

## Features

- Generates a secure RSA 4096-bit private key (using `tls_private_key`).
- Uploads the public key to AWS as an EC2 Key Pair (using `aws_key_pair`).
- Outputs the private key (PEM) for local use.

## Usage

```hcl
module "ssh_key" {
  source = "./modules/aws/key-pair"

  key_name = "my-secure-key"
}
```

## Architecture Decisions

### Combined Module Strategy
We chose to keep `tls_private_key` (crypto) and `aws_key_pair` (AWS resource) **combined** in this single module.

**Pros:**
*   **Convenience:** Simplifies the standard use-case (create identity -> use identity).
*   **Safety:** Prevents "orphaned" keys (generated but not uploaded) or "empty" key pairs.

**Cons:**
*   **Multi-Region limitations:** Since `aws_key_pair` is a regional resource, this module is tied to the provider's region. You cannot reuse the *exact same* private key across regions using just this module instance.

### Future Multi-Region Enhancement
If you ever need to use the *same* private key across multiple regions (e.g., `us-east-1` and `eu-west-1`), you should refactor as follows (possibly improving the proposed module names):

1.  **Split this module** into two smaller modules:
    *   `secret-generator` (wrapper for `tls_private_key` only).
    *   `key-uploader` (wrapper for `aws_key_pair` only).
2.  **Implementation Pattern:**
    ```hcl
    # 1. Generate Secret once
    module "global_secret" { source = "./modules/secret-generator" }

    # 2. Upload to Region A
    module "us_key" {
      source = "./modules/key-uploader"
      public_key = module.global_secret.public_key
      providers = { aws = aws.us_east_1 }
    }

    # 3. Upload to Region B
    module "eu_key" {
      source = "./modules/key-uploader"
      public_key = module.global_secret.public_key
      providers = { aws = aws.eu_west_1 }
    }
    ```
