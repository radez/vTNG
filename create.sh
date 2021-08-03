source ./vars.sh

set -e
#set -x

####### Create Virtual Machines ########

# Create Disk images
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
       qemu-img create -b $LV_DIR/$x.img -f qcow2 $LV_DIR/$l-$x.qcow2 30G
    done
done
for l in $LEAVES; do
    for n in $NODES; do
        qemu-img create -b $LV_DIR/cirros-0.5.2-x86_64-disk.img -f qcow2 $LV_DIR/$l-$n.qcow2 30G
    done
done

# Create Virtual machines
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        virt-install --name $l-$x --memory 1024 --vcpus 1 --disk $LV_DIR/$l-$x.qcow2 --import --noautoconsole --noreboot --network none --os-variant unknown
    done
done
for l in $LEAVES; do
    for x in $NODES; do
        virt-install --name $l-$x --memory 512 --vcpus 1 --disk $LV_DIR/$l-$x.qcow2 --import --noautoconsole --noreboot --network none --os-variant unknown
    done
done

####### Setup UDP vNics to interconnect VMs #######

# UDP Ports numbers are 5 digit generated in this construct:
# Digit 1: 1 for spine switch, 2 for leaf switch
# Digit 2: 1 and 0 must be opposite on each side of tunnel
# Digit 3: switch name number ex: spine0 = 0, leaf2 = 2
# Digits 4&5: 99/98 for vqfx/pfx interconnect, node number for nodes


# setup networking
for l in $SPINES $LEAVES; do
    # Add mgmt and interconnect networks to switches
    for x in $SWITCHES; do
        if [ "$x" = "vqfx" ] ;then
            src_pre="${UDPPRE[${l:0:-1}]}1"
            local_pre="${UDPPRE[${l:0:-1}]}0"
        else
            src_pre="${UDPPRE[${l:0:-1}]}0"
            local_pre="${UDPPRE[${l:0:-1}]}1"
        fi
        echo "Adding interfaces to $l-$x"
        virsh attach-interface --domain $l-$x --type network --model e1000 --source default --persistent
        for p in 99 98; do
            sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$l-$x.xml
            sed -i "s/SOURCEPORT/$src_pre${l: -1}$p/" /etc/libvirt/qemu/$l-$x.xml
            sed -i "s/LOCALPORT/$local_pre${l: -1}$p/" /etc/libvirt/qemu/$l-$x.xml
            echo "Configured $l-$x interconnect"
        done
    done
done

for l in $LEAVES; do
    x=vqfx

    # connect leaves to spines
    for s in $SPINES; do
        src_pre=${UDPPRE[${l:0:-1}]}0
        local_pre=${UDPPRE[${l:0:-1}]}1
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$s-$x.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0${UPLINK[${s: -1}]}/" /etc/libvirt/qemu/$s-$x.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0${UPLINK[${s: -1}]}/" /etc/libvirt/qemu/$s-$x.xml
    done

    # Add switch ports to vqfx switches
    src_pre=${UDPPRE[${l:0:-1}]}1
    local_pre=${UDPPRE[${l:0:-1}]}0
    for p in $PORTS; do
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$l-$x.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0$p/" /etc/libvirt/qemu/$l-$x.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0$p/" /etc/libvirt/qemu/$l-$x.xml
    done
done

# connect server nodes to leaf switches
for l in $LEAVES; do
    src_pre=${UDPPRE[${l:0:-1}]}0
    local_pre=${UDPPRE[${l:0:-1}]}1
    for n in $NODES; do
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$l-$n.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0${n: -1}/" /etc/libvirt/qemu/$l-$n.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0${n: -1}/" /etc/libvirt/qemu/$l-$n.xml
    done
done

systemctl reload libvirtd
sleep 1


####### Show me Libvirt Networking Config #######
# clear the file
echo "" > libvirt_networking
# list interfaces
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        echo "$l-$x" >> libvirt_networking
        virsh domiflist $l-$x >> libvirt_networking
    done
done
for l in $LEAVES; do
    for x in $NODES; do
        echo "$l-$x" >> libvirt_networking
        virsh domiflist $l-$x >> libvirt_networking
    done
done

####### Start the Virtual Machines #######
# Start switches
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        virsh start $l-$x
    done
done

# Start  nodes
for l in $LEAVES; do
    for n in $NODES; do
        virsh start $l-$n
    done
done

####### Configure the Switches #######

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

    echo ""
    echo "Installing ssh keys on $l-vqfx"
TERM=xterm expect -c "
spawn bash -c \"ssh-copy-id -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i /home/dradez/.ssh/id_ed25519.pub root@$SWIP\"
expect {
  timeout { exit 1 }
  eof { exit 1 }
  \"root*password:\"
}
send \"Juniper\r\"
expect {
  timeout { exit 1 }
  \"Number of key(s) added: 1\"
}
expect \"Number of key(s) added: 1\"
"

    echo ""
    echo "Configuring interconnect IP on vQFX for $l-vqfx"
TERM=xterm expect -c "
set timeout 300
spawn bash -c \"ssh -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$SWIP\"
expect {
  timeout { exit 1 }
  eof { exit 1 }
  \"root*password:\"
}
send \"Juniper\r\"
expect \"root@:RE:0%\"
send \"cli\r\"
expect \"root>\"
send \"config\r\"
expect \"root#\"
send \"deactivate system syslog user *\r\"
expect \"root#\"
send \"set interfaces em1 unit 0 family inet address 169.254.0.2/24\r\"
expect \"root#\"
send \"set system host-name $l\r\"
expect \"root#\"
send \"delete routing-options static\r\"
expect \"root#\"
send \"set protocols bgp group vTNG type external\r\"
expect \"root#\"
send \"set protocols bgp group vTNG export send-direct\r\"
expect \"root#\"
send \"set protocols bgp group vTNG hold-time 10\r\"
expect \"root#\"
send \"set protocols bgp group vTNG family inet unicast\r\"
expect \"root#\"
send \"set protocols bgp group vTNG multipath multiple-as\r\"
expect \"root#\"
send \"set policy-options policy-statement send-direct term 1 from protocol direct\r\"
expect \"root#\"
send \"set policy-options policy-statement send-direct term 1 then accept\r\"
expect \"root#\"
send \"set policy-options policy-statement PFE-ECMP then load-balance per-packet\r\"
expect \"root#\"
send \"set routing-options forwarding-table export PFE-ECMP\r\"
expect \"root#\"
send \"commit\r\"
expect \"root@$l#\"
send \"exit\r\"
expect \"root@$l>\"
send \"restart chassis-control\r\"
expect \"root@$l>\"
send \"exit\r\"
expect \"root@:RE:0%\"
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
expect \"root@$l:RE:0%\"
send \"cli\r\"
expect \"root@$l>\"
send \"config\r\"
expect \"root@$l#\"
send \"set interfaces lo0 unit 0 family inet address 10.0.${l: -1}.1/32\r\"
expect \"root@$l#\"
send \"set routing-options autonomous-system 420000000${l: -1}\r\"
expect \"root@$l#\"
foreach h [list $LEAVES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/\$index unit 0 family inet address 172.16.${l: -1}.[expr \$index *2]/31\r\"
    expect \"root@$l#\"
    send \"set protocols bgp group vTNG neighbor 172.16.${l: -1}.[expr [expr \$index *2] +1] peer-as 420000001\$index\r\"
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
send \"set interfaces lo0 unit 0 family inet address 10.0.${l: -1}.2/32\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching vlan members default\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching vlan members default\r\"
expect \"root@$l#\"
send \"set routing-options autonomous-system 420000001${l: -1}\r\"
expect \"root@$l#\"
foreach h [list $SPINES] {
    set index [string range \$h end end]
    send \"set interfaces xe-0/0/[lindex \$uplinks \$index] unit 0 family inet address 172.16.\$index.$((${l: -1}*2+1))/31\r\"
    expect \"root@$l#\"
    send \"set protocols bgp group vTNG neighbor 172.16.\$index.$((${l: -1}*2)) peer-as 420000000\$index\r\"
    expect \"root@$l#\"
}
send \"set interfaces irb unit 1 family inet address 192.168.${l: -1}.254/24\r\"
expect \"root@$l#\"
send \"set vlans default l3-interface irb.1\r\"
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
