source ./vars.sh

# pause Virtual machines
for l in $SPINES $LEAVES; do
    for x in $SWITCHES $NODES; do
        virsh suspend $l-$x
    done
done
