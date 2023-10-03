
## Overview

This is a mono repository for a single Kubernetes cluster. Used as a learning and education project that provided a hands-on approach for mastering Kubernetes cluster configuratins
and best practices. Adherance to Infrastructure as Code (IaC) and GitOps practices by using tools like [Terraform](https://www.terraform.io/), [Ansible](https://www.ansible.com/),
[Kubernetes](https://www.kubernetes.io/), [Flux](https://fluxcd.io), [Renovate](https://www.mend.io/renovate/) and [GitHub Actions](https://github.com/features/actions).

## Kubernetes

This cluster is provisioned to a vSphere Lab, leveraging a [no-code](https://developer.hashicorp.com/terraform/tutorials/cloud/no-code-provisioning) module approach using Terraform.
Previous generations of this cluster were provisioned using RaspberryPi's as hyper-converged host nodes.
