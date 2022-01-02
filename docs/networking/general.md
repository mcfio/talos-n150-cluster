# Overview

This is an overview of the cluster's current networking topology.

```mermaid
graph LR
  internet([Internet])-.->gateway[Gateway]
  subgraph network
    gateway-->|VLAN30|nw1[Client Network]
    gateway-->|VLAN45|nw2[Cluster Network]
  end
```

The `Gateway` component performs its typical role of router as well as firewall and governs perimeter access into my network and between network segments.

The following table describes the current network and CIDR allocations

| Network                | CIDR              |
| ---------------------- | ----------------- |
| Client Network         | `192.168.30.0/24` |
| Cluster Nodes          | `192.168.45.0/24` |
| Cluster Pod Subnet     | `10.244.0.0/18`   |
| Cluster Service Subnet | `10.244.64.0/20`  |

The cluster network is implemented as an overlay (non-encapsulated) network between `Cluster Nodes` and no direct Layer3 access to the Pod or Service Subnets is possible. To expose services
in the cluster to the `Client Network` and `Internet` the cluster implements Ingress/Egress controllers exposing `type: loadBalancer` services on the `Cluster Nodes` network.

## Highly Available Control Plane

In typical higly available control plane clusters an external VIP provider is used to provide connectivity to the control plane API servers. Since this cluster is considered _bare metal_ an alternative solution is required.

```mermaid
graph TD;
  client([Client]).->VIP[VIP];
  subgraph cluster_network
    VIP-->CP1[Control Plane<br>Node 1];
    VIP-->CP2[Control Plane<br>Node 2];
    VIP-->CP3[Control Plane<br>Node 3];
  end;
```

This cluster is configured as a stacked control plane and uses a software based solution to create the necessary components to provide a fault-tolerate control plane access layer. These
components are `keepalived` - used to advertise the Layer2 IP address for the _VIP_, `haproxy` - the _load balancer_ that proxies `kube-apiserver` traffic between the 3 control plane nodes.
`keepalived` and `haproxy` are deployed as _static pods_ whos manifests are deployed at cluster init. The configuration generally looks like this;

![HA Control Plane](images/ha-control-plane.svg)

> It's important to note that, as currently configured, `keepalived` only moves the VIP between nodes when it can no longer detect network connectivity. This means if the node is up, `keepalived` is available.
