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

    echo ""
    echo "Configuring Common vQFX Configs for $l-vqfx"
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
expect \"root*>\"
send \"config\r\"
expect \"root*#\"

### All Switches Common Underlay Configs ###
send \"set protocols bgp group UNDERLAY type external\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY export send-direct\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY hold-time 10\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY family inet unicast loops 5\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY multipath\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY advertise-peer-as\r\"
expect \"root*#\"
send \"set policy-options policy-statement send-direct term 1 from protocol direct\r\"
expect \"root*#\"
send \"set policy-options policy-statement send-direct term 1 then accept\r\"
expect \"root*#\"
send \"set policy-options policy-statement LB-policy then load-balance per-packet\r\"
expect \"root*#\"
send \"set routing-options forwarding-table export LB-policy\r\"
expect \"root*#\"


send \"commit\r\"
expect \"root@$l#\"
send \"exit\r\"
expect \"root@$l>\"
send \"restart chassis-control\r\"
expect \"root@$l>\"
send \"exit\r\"
expect \"root@*:RE:0%\"
send \"exit\r\"
"

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
send \"set interfaces lo0 unit 0 family inet address 10.0.0.1${l: -1}/32 primary\r\"
expect \"root@$l#\"


### Spine Switches Underlay Configs ###
send \"set routing-options router-id 10.0.0.1${l: -1}\r\"
expect \"root@$l#\"
send \"set routing-options autonomous-system 65001\r\"
expect \"root@$l#\"
send \"set protocols bgp group UNDERLAY peer-as 65000\r\"
expect \"root@$l#\"

foreach h [list $LEAVES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/\$index unit 0 family inet address 172.16.${l: -1}.[expr \$index *2]/31\r\"
    expect \"root@$l#\"
    send \"set protocols bgp group UNDERLAY neighbor 172.16.${l: -1}.[expr [expr \$index *2] +1]\r\"
    expect \"root@$l#\"
}


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
send \"set interfaces lo0 unit 0 family inet address 10.0.0.2${l: -1}/32 primary\r\"
expect \"root@$l#\"
send \"set routing-options router-id 10.0.0.2${l: -1}\r\"
expect \"root@$l#\"
send \"set routing-options autonomous-system 65000\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching vlan members default\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching vlan members 3\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/2 unit 0 family ethernet-switching interface-mode trunk\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/2 unit 0 family ethernet-switching vlan members 7\r\"
expect \"root@$l#\"

### Leaf Switches Underlay Configs ###
send \"set protocols bgp group UNDERLAY peer-as 65001\r\"
expect \"root*#\"
send \"set protocols bgp group UNDERLAY local-as 65000 loops 1\r\"
expect \"root*#\"
foreach h [list $SPINES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/[lindex \$uplinks \$index] unit 0 family inet address 172.16.\$index.$((${l: -1}*2+1))/31\r\"
    expect \"root@$l#\"
    send \"set protocols bgp group UNDERLAY neighbor 172.16.\$index.$((${l: -1}*2))\r\"
    expect \"root@$l#\"
}
send \"set interfaces irb unit 0 family inet address 192.168.${l: -1}.254/24\r\"
expect \"root*#\"
send \"set vlans default l3-interface irb.0\r\"
expect \"root*#\"


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
