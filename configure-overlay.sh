source ./vars.sh

set -e
#set -x
# wait for switch mgmt ip addresses
for l in $SPINES $LEAVES; do
    echo ""
    echo ""
    echo "Waiting for IP on $l-vqfx"
    while [ -z "$SWIP" ]; do
        SWMAC=$(virsh domiflist $l-vqfx | grep network | awk '{print $5}')
        SWIP=$(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)
        if [ -z "$SWIP" ]; then sleep 5; echo -n '.'; fi
    done

    sleep 1

    if [[ "$l" == *"spine"* ]]; then
        echo "Configuring spine addresses and routes on $l-vqfx"

TERM=xterm expect -c "
set timeout 300
spawn bash -c \"ssh -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$SWIP\"
expect {
  timeout { exit 1 }
  eof { exit 1 }
  \"root*password:\"
}
send \"Juniper\r\"
expect \"root@*:RE:0%\"
send \"cli\r\"
expect \"root@$l>\"
send \"config\r\"
expect \"root@$l#\"
### Spine Switches Overlay Configs ###
send \"set protocols bgp group EVPN-OVERLAY type internal\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY local-address 10.0.0.1${l: -1}\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY family evpn signaling\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY cluster $((${l: -1}+1)).$((${l: -1}+1)).$((${l: -1}+1)).$((${l: -1}+1))\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY local-as 65010\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY multipath\r\"
expect \"root@$l#\"
foreach h [list $SPINES] {
    set index [string range \$h end end]
    if {\"$l\" != \$h} {
        send \"set protocols bgp group EVPN-OVERLAY neighbor 10.0.0.1\$index\r\"
        expect \"root@$l#\"
    }
}
foreach h [list $LEAVES] {
    set index [string range \$h end end]
    send \"set protocols bgp group EVPN-OVERLAY neighbor 10.0.0.2\$index\r\"
    expect \"root@$l#\"
}
send \"set protocols evpn encapsulation vxlan\r\"
expect \"root@$l#\"
send \"set protocols evpn multicast-mode ingress-replication\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term switch_options_comm from community switch_options_comm\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term switch_options_comm then accept\r\"
expect \"root@$l#\"
send \"set policy-options community switch_options_comm members target:65000:2\r\"
expect \"root@$l#\"
send \"set switch-options vtep-source-interface lo0.0\r\"
expect \"root@$l#\"
send \"set switch-options route-distinguisher 10.0.0.1${l: -1}:1\r\"
expect \"root@$l#\"
send \"set switch-options vrf-import EVPN_VRF_IMPORT\r\"
expect \"root@$l#\"
send \"set switch-options vrf-target target:65000:2\r\"
expect \"root@$l#\"
send \"set switch-options vrf-target auto\r\"
expect \"root@$l#\"


send \"set interfaces lo0 unit 3 family inet address 10.1${l: -1}.0.3/32 \r\"
expect \"root@$l#\"
send \"set interfaces lo0 unit 7 family inet address 10.1${l: -1}.0.7/32 \r\"
expect \"root@$l#\"
send \"set interfaces irb unit 3 family inet address 192.168.3.1${l: -1}/24 virtual-gateway-address 192.168.3.254\r\"
expect \"root@$l#\"
send \"set interfaces irb unit 7 family inet address 192.168.7.1${l: -1}/24 virtual-gateway-address 192.168.7.254\r\"
expect \"root@$l#\"
send \"set protocols evpn extended-vni-list \[ 3 7 \]\r\"
expect \"root@$l#\"

send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0001 from community vrf0001\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0001 then accept\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0003 from community vni0003\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0003 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vni0003 members target:10003:3\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 instance-type vrf\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 interface irb.3\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 interface lo0.3\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 route-distinguisher 10.0.0.1${l: -1}:2001\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 vrf-target target:10001:1\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 routing-options auto-export\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vlan-id 3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 l3-interface irb.3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vxlan vni 3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vxlan ingress-node-replication\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement vrf0001_vrf_imp term 1 from community vrf0001\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement vrf0001_vrf_imp term 1 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vrf0001 members target:10001:1\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0001 vrf-import vrf0001_vrf_imp\r\"
expect \"root@$l#\"


send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0002 from community vrf0002\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0002 then accept\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0007 from community vni0007\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0007 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vni0007 members target:10003:7\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 instance-type vrf\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 interface irb.7\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 interface lo0.7\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 route-distinguisher 10.0.0.1${l: -1}:2002\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 vrf-target target:10001:2\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 routing-options auto-export\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vlan-id 7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 l3-interface irb.7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vxlan vni 7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vxlan ingress-node-replication\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement vrf0002_vrf_imp term 1 from community vrf0002\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement vrf0002_vrf_imp term 1 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vrf0002 members target:10001:2\r\"
expect \"root@$l#\"
send \"set routing-instances vrf0002 vrf-import vrf0002_vrf_imp\r\"
expect \"root@$l#\"

send \"commit\r\"
expect \"root@$l#\"
send \"exit\r\"
expect \"root@$l>\"
send \"exit\r\"
expect \"root@$l:RE:0%\"
send \"exit\r\"
"
    fi

    if [[ "$l" == *"leaf"* ]]; then
        echo "Configuring leaf addresses and routes on $l-vqfx"

TERM=xterm expect -c "
set timeout 300
set uplinks [list $(echo ${UPLINK[@]})]
spawn bash -c \"ssh -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$SWIP\"
expect {
  timeout { exit 1 }
  eof { exit 1 }
  \"root*password:\"
}
send \"Juniper\r\"
expect \"root@$l:RE:0%\"
send \"cli\r\"
expect \"root@$l>\"
send \"config\r\"
expect \"root@$l#\"

### Leaf Switches Overlay Configs ###
send \"set protocols bgp group EVPN-OVERLAY type internal\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY local-address 10.0.0.2${l: -1}\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY family evpn signaling\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY local-as 65010\r\"
expect \"root@$l#\"
send \"set protocols bgp group EVPN-OVERLAY multipath\r\"
expect \"root@$l#\"

foreach h [list $SPINES] {
    set index [string range \$h end end]
    send \"set protocols bgp group EVPN-OVERLAY neighbor 10.0.0.1\$index\r\"
    expect \"root@$l#\"
}
foreach h [list $LEAVES] {
    set index [string range \$h end end]
    if {\"$l\" != \$h} {
        send \"set protocols bgp group EVPN-OVERLAY neighbor 10.0.0.2\$index\r\"
        expect \"root@$l#\"
    }
}

### Leaf Switches VXLAN Configs ###
send \"set protocols evpn encapsulation vxlan\r\"
expect \"root@$l#\"
send \"set protocols evpn multicast-mode ingress-replication\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term switch_options_comm from community switch_options_comm\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term switch_options_comm then accept\r\"
expect \"root@$l#\"
send \"set policy-options community switch_options_comm members target:65000:2\r\"
expect \"root@$l#\"
send \"set switch-options vtep-source-interface lo0.0\r\"
expect \"root@$l#\"
send \"set switch-options route-distinguisher 10.0.0.2${l: -1}:1\r\"
expect \"root@$l#\"
send \"set switch-options vrf-import EVPN_VRF_IMPORT\r\"
expect \"root@$l#\"
send \"set switch-options vrf-target target:65000:2\r\"
expect \"root@$l#\"
send \"set switch-options vrf-target auto\r\"
expect \"root@$l#\"


send \"set protocols evpn extended-vni-list \[ 3 7 \]\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0001 from community vrf0001\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0001 then accept\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0003 from community vni0003\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0003 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vrf0001 members target:10001:1\r\"
expect \"root@$l#\"
send \"set policy-options community vni0003 members target:10003:3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vlan-id 3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vxlan vni 3\r\"
expect \"root@$l#\"
send \"set vlans vlan0003 vxlan ingress-node-replication\r\"
expect \"root@$l#\"


send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0002 from community vrf0002\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vrf0002 then accept\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0007 from community vni0007\r\"
expect \"root@$l#\"
send \"set policy-options policy-statement EVPN_VRF_IMPORT term vni0007 then accept\r\"
expect \"root@$l#\"
send \"set policy-options community vrf0002 members target:10001:2\r\"
expect \"root@$l#\"
send \"set policy-options community vni0007 members target:10003:7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vlan-id 7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vxlan vni 7\r\"
expect \"root@$l#\"
send \"set vlans vlan0007 vxlan ingress-node-replication\r\"
expect \"root@$l#\"


send \"commit\r\"
expect \"root@$l#\"
send \"exit\r\"
expect \"root@$l>\"
send \"exit\r\"
expect \"root@$l:RE:0%\"
send \"exit\r\"
"
fi
    unset SWIP
done



SWMAC=$(virsh domiflist $l-vqfx | grep network | awk '{print $5}')
SWIP=$(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)

echo ""    
echo ""    
# print switch IP addresses
for l in $SPINES $LEAVES; do
  SWMAC=$(virsh domiflist $l-vqfx | grep network | awk '{print $5}')
  echo "$l-vqfx: $SWMAC :: $(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)"
done

echo ""
echo ""
echo "Libvirt Networking is recorded in the file libvirt_networking"
