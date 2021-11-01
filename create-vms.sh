source ./vars.sh

set -e
#set -x

DELAY=5

####### Create Virtual Machines ########

# Create Disk images
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
       qemu-img create -b $LV_DIR/${SWIMAGES[$x]} -f qcow2 $LV_DIR/$l-$x.qcow2 30G
    done
done
for l in $LEAVES; do
    for n in $NODES; do
        qemu-img create -b $LV_DIR/$NODE -f qcow2 $LV_DIR/$l-$n.qcow2 30G
    done
done

# Create Virtual machines
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        virt-install --name $l-$x --memory $SWMEM --vcpus $SWCPU --disk $LV_DIR/$l-$x.qcow2 --import --noautoconsole --noreboot --network none --os-variant generic
    done
done
for l in $LEAVES; do
    for x in $NODES; do
        virt-install --name $l-$x --memory $NODEMEM --vcpus $NODECPU --disk $LV_DIR/$l-$x.qcow2 --import --noautoconsole --noreboot --network none --os-variant generic
        if [ -n "$NODECDROM" ]; then
            if [ ! -f /path/to/file ]; then
                pushd fedora-cloud-init
                genisoimage -output $LV_DIR/$NODECDROM -volid cidata -joliet -rock user-data meta-data
                popd
            fi
            virsh attach-disk $l-$x --config $LV_DIR/$NODECDROM hdb --type cdrom
        fi
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

ct=0
####### Start the Virtual Machines #######
# Start switches
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        sleep $((ct*$DELAY)) && virsh start $l-$x &
        echo "Scheduled $l-$x for start in $((ct*$DELAY)) seconds"
        ct=$((ct+1))
    done
done

# Start  nodes
for l in $LEAVES; do
    for n in $NODES; do
        sleep $((ct*$DELAY)) && virsh start $l-$n &
        echo "Scheduled $l-$n for start in $((ct*$DELAY)) seconds"
        # don't increase start delay. starte all the nodes at once
        #ct=$((ct+1))
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
        if [ -z "$SWIP" ]; then sleep 5; echo -n '.'; fi
    done

    sleep 1

    echo ""
    if [ -z "$PUBKEY" ]; then
        echo "Skipping pubkey install"
    elif [ -f "$PUBKEY" ]; then
        echo "Installing ssh keys on $l-vqfx"
TERM=xterm expect -c "
spawn bash -c \"ssh-copy-id -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $PUBKEY root@$SWIP\"
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
    fi

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
send \"deactivate system syslog user *\r\"
expect \"root*#\"
send \"set interfaces em1 unit 0 family inet address 169.254.0.2/24\r\"
expect \"root*#\"
send \"set system host-name $l\r\"
expect \"root*#\"
send \"delete routing-options\r\"
expect \"root*#\"
send \"wildcard delete interfaces xe-*\r\"
expect \"Delete * objects? *\"
send \"yes\r\"
expect \"root*#\"
send \"wildcard delete interfaces et-*\r\"
expect \"Delete * objects? *\"
send \"yes\r\"
expect \"root*#\"

send \"commit\r\"
expect \"root@$l#\"
send \"exit\r\"
expect \"root@$l>\"
send \"exit\r\"
expect \"root@$l:RE:0%\"
send \"exit\r\"
"

    unset SWIP
done
