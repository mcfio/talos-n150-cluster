# Cilium BGP Configuration

## UniFi UDM Pro

```sh
!
frr defaults traditional
hostname $UDMP_HOSTNAME
log syslog informational
!
router bgp 64513
 bgp ebgp-requires-policy
 bgp router-id 192.168.45.1
 maximum-paths 2
 !
 neighbor cilium peer-group
 neighbor cilium remote-as 64515
 neighbor cilium activate
 neighbor cilium soft-reconfiguration inbound
 !
 neighbor 192.168.45.75 peer-group cilium
 neighbor 192.168.45.76 peer-group cilium
 neighbor 192.168.45.77 peer-group cilium
 !
 address-family ipv4 unicast
  redistribute connected
  neighbor cilium activate
  neighbor cilium route-map ALLOW-ALL in
  neighbor cilium route-map ALLOW-ALL out
  neighbor cilium next-hop-self
 exit-address-family
exit
!
route-map ALLOW-ALL permit 10
exit
!
end
```
