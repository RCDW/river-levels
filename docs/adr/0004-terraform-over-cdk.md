# 4. IaC: Terraform over AWS CDK / CloudFormation

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

The AWS hosting (ADR 0003) is provisioned as code. The main options were
Terraform, AWS CDK, and raw CloudFormation.

## Decision

Use **Terraform** (HCL), with remote state in S3 and native S3 state locking.

Reasons:

- **Industry standard / job-relevant.** Terraform is the dominant IaC tool in
  data and cloud roles — worth knowing well for the job search.
- **A deliberate choice to learn Terraform.** This site is partly a vehicle for
  getting hands-on with Terraform ahead of the IaC-heavy `river-levels`
  project.

## Consequences

- **+** Directly builds a sought-after, transferable skill.
- **+** The same toolchain and skills carry straight into `river-levels`.
- **−** Less native AWS integration than CDK/CloudFormation (no imperative
  constructs), and managing remote state is on us. Acceptable for the learning
  goal.
