# Cilium BGP Configuration

## UniFi UDM Pro

```sh
router bgp 64513
  bgp router-id 192.168.45.1
  neighbor cilium peer-group
  neighbor cilium remote-as 64515
  bgp listen range 192.168.45.0/24 peer-group cilium
  !
  address-family ipv4 unicast
    neighbor cilium next-hop-self
    neighbor cilium soft-reconfiguration inbound
    neighbor cilium route-map ALLOW-ALL in
    neighbor cilium route-map ALLOW-ALL out
  exit-address-family
exit
!
route-map ALLOW-ALL permit 10
exit
```
