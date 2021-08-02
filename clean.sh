source ./vars.sh

# delete Virtual machines
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
        virsh destroy $l-$x
        virsh undefine $l-$x --remove-all-storage
    done
done
for l in $LEAVES; do
    for x in $NODES; do
        virsh destroy $l-$x
        virsh undefine $l-$x --remove-all-storage
    done
done

# ensure deleted Disk images
for l in $SPINES $LEAVES; do
    for x in $SWITCHES; do
       rm -f $LV_DIR/$l-$x.qcow2
    done
done
for l in $LEAVES; do
    for n in $NODES; do
        rm -f $LV_DIR/$l-$n.qcow2
    done
done
