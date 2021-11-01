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
        echo "Configuring OSPF Underlay Routing on $l-vqfx"

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

send \"set routing-options router-id 172.31.0.1${l: -1}\r\"
expect \"root@$l#\"

### Configure Interfaces for OSPF ###
foreach h [list $LEAVES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/\$index unit 0 family inet address 172.16.${l: -1}.[expr \$index *2]/31\r\"
    expect \"root@$l#\"
    send \"set protocols ospf area 0.0.0.0 interface xe-0/0/\$index\r\"
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

send \"set routing-options router-id 172.31.0.2${l: -1}\r\"
expect \"root@$l#\"

### Leaf Switches Underlay Configs ###
foreach h [list $SPINES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/[lindex \$uplinks \$index] unit 0 family inet address 172.16.\$index.$((${l: -1}*2+1))/31\r\"
    expect \"root*#\"
    send \"set protocols ospf area 0.0.0.0 interface xe-0/0/[lindex \$uplinks \$index]\r\"
    expect \"root*#\"
}
send \"set interfaces irb unit 0 family inet address 192.168.${l: -1}.254/24\r\"
expect \"root*#\"
send \"set vlans default l3-interface irb.0\r\"
expect \"root*#\"
send \"set protocols ospf area 0.0.0.0 interface irb.0\r\"
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
