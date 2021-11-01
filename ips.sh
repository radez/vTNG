source ./vars.sh

echo ""    
echo ""    

if [ "$1" == '-t' ]; then
  declare -a tmux_spines
  declare -a tmux_leaves
  for l in $SPINES; do
    SWMAC=$(virsh domiflist $l-vqfx | grep default | awk '{print $5}')
    tmux_spines[${l: -1}]=$(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)
  done
    tmux new-window "tmux split-pane -h \"tmux split-pane -h \\\"ssh root@${tmux_spines[1]}\\\"; tmux select-layout even-horizontal; ssh root@${tmux_spines[0]}\""
  for l in $LEAVES; do
    SWMAC=$(virsh domiflist $l-vqfx | grep default | awk '{print $5}')
    tmux_leaves[${l: -1}]=$(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)
  done
    tmux new-window "tmux split-pane -h \"tmux split-pane -h \\\"tmux split-pane -h \\\\\\\"ssh root@${tmux_leaves[2]}\\\\\\\"; ssh root@${tmux_leaves[1]}\\\"; tmux select-layout even-horizontal; ssh root@${tmux_leaves[0]}\""
else
  # print switch IP addresses
  for l in $SPINES $LEAVES; do
    SWMAC=$(virsh domiflist $l-vqfx | grep default | awk '{print $5}')
    echo "$l-vqfx: $SWMAC :: $(virsh net-dhcp-leases default | grep $SWMAC | awk '{print $5}' | cut -d / -f 1)"
  done
fi
