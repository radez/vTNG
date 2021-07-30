LV_DIR=/var/lib/libvirt/images
SWITCHES="vqfx vqfx-pfe"
SPINES="spine0"
LEAVES="leaf1 leaf2"
NODES="node0"
PORTS="0 1 2 3 4 5"
UPLINK="5"
SUBNETS=("10.0.0" "192.168.37" "192.168.73")

set -e

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

# setup networking
for l in $SPINES $LEAVES; do
    # Add mgmt and interconnect networks to switches
    for x in $SWITCHES; do
        if [ "$x" = "vqfx" ] ;then
            src_pre=11
            local_pre=10
        else
            src_pre=10
            local_pre=11
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
        src_pre=10
        local_pre=11
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$s-$x.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0$UPLINK/" /etc/libvirt/qemu/$s-$x.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0$UPLINK/" /etc/libvirt/qemu/$s-$x.xml
    done

    # Add switch ports to vqfx switches
    src_pre=11
    local_pre=10
    for p in $PORTS; do
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$l-$x.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0$p/" /etc/libvirt/qemu/$l-$x.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0$p/" /etc/libvirt/qemu/$l-$x.xml
    done
done

# connect server nodes to leaf switches
for l in $LEAVES; do
    src_pre=10
    local_pre=11
    for n in $NODES; do
        sed -i '/<serial/e cat udp.xml' /etc/libvirt/qemu/$l-$n.xml
        sed -i "s/SOURCEPORT/$src_pre${l: -1}0${n: -1}/" /etc/libvirt/qemu/$l-$n.xml
        sed -i "s/LOCALPORT/$local_pre${l: -1}0${n: -1}/" /etc/libvirt/qemu/$l-$n.xml
    done
done

systemctl reload libvirtd
sleep 1

# list interfaces
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        echo "$l-$x"
        virsh domiflist $l-$x
    done
done
for l in $LEAVES; do
    for x in $NODES; do
        echo "$l-$x"
        virsh domiflist $l-$x
    done
done

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

# wait for switch mgmt ip addresses
for l in $SPINES $LEAVES; do
    echo ""
    echo ""
    echo "Waiting for IP on $l-vqfx"
    while [ -z "$SWIP" ]; do
        SWMAC=$(virsh domiflist $l-vqfx | grep network | awk '{print $5}')
        SWIP=$(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)
        sleep 5
    done

    echo "Configuring interconnect IP on vQFX for $l-vqfx"
    echo "Configuring connection to spine from vQFX $l-vqfx"
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
send \"set interfaces xe-0/0/5 unit 0 family inet address 172.16.${l: -1}.2/24\r\"
expect \"root#\"
send \"set system host-name $l\r\"
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
        echo "Configuring connection to leaves on vQFX $l-vqfx"

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
send \"set interfaces lo0 unit 0 family inet address 10.0.0.1/32\r\"
expect \"root@$l#\"
send \"set interfaces lo0 unit 0 family inet address 10.0.0.2/32\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family inet address 172.16.1.1/24\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family inet address 172.16.2.1/24\r\"
expect \"root@$l#\"
send \"delete routing-options static\r\"
expect \"root@$l#\"
send \"set routing-options static route 192.168.37.0/24 next-hop 172.16.1.2\r\"
expect \"root@$l#\"
send \"set routing-options static route 192.168.73.0/24 next-hop 172.16.2.2\r\"
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
        echo "Configuring connection to servers on vQFX $l-vqfx"

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
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/0 unit 0 family ethernet-switching vlan members default\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching interface-mode access\r\"
expect \"root@$l#\"
send \"set interfaces xe-0/0/1 unit 0 family ethernet-switching vlan members default\r\"
expect \"root@$l#\"
send \"set interfaces irb unit 1 family inet address ${SUBNETS[${l: -1}]}.1/24\r\"
expect \"root@$l#\"
send \"set vlans default l3-interface irb.1\r\"
expect \"root@$l#\"
send \"delete routing-options static\r\"
expect \"root@$l#\"
send \"set routing-options static route 0.0.0.0/0 next-hop 172.16.${l: -1}.1\r\"
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

# On Leaf 1:
# set routing-options static route 172.16.2.0/24 next-hop 172.16.1.1
# can ping 172.16.2.1
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
