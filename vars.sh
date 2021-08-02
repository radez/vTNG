LV_DIR=/var/lib/libvirt/images
SWITCHES="vqfx vqfx-pfe"
SPINES="spine0 spine1"
LEAVES="leaf0 leaf1"
NODES="node0"
PORTS="0 1 2 3 4 5"
UPLINK=(4 5)

declare -A UDPPRE
UDPPRE=( ['spine']=1 ['leaf']=2 )

