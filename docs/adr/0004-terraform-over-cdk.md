# 4. IaC: Terraform over AWS CDK / CloudFormation

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The AWS hosting (ADR 0003) is provisioned as code. The options were Terraform,
AWS CDK, and raw CloudFormation.

## Decision

Use **Terraform** (HCL), with remote state in S3 and native S3 state locking.
This repo keeps its **own** state (key `river-levels/terraform.tfstate`) in the
shared state bucket, so it can never accidentally manage the hub's resources.

Reasons:

- **Industry standard / job-relevant.** Terraform is the dominant IaC tool in
  data and cloud roles.
- **Consistency with the hub.** The same toolchain and patterns as
  reecewall.dev, so one mental model covers both repos.

## Consequences

- **+** Builds a sought-after, transferable skill; one IaC pattern across repos.
- **+** Isolated state keeps the blast radius contained to this repo.
- **-** Less native AWS integration than CDK (no imperative constructs), and
  managing remote state is on us. Acceptable.
