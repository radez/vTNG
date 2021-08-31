#!/bin/bash

# User specific settings
PUBKEY=/home/dradez/.ssh/id_ed25519.pub

# Environment settings
# Disk Images
LV_DIR=/var/lib/libvirt/images
VQFXRE=vqfx-20.2R1.10-re-qemu.qcow2
VQFXPFE=vqfx-20.2R1-2019010209-pfe-qemu.qcow2
NODE=cirros-0.5.2-x86_64-disk.img
#NODE=Fedora-Cloud-Base-34-1.2.x86_64.qcow2


# Deployment Variables
# Each item is the name of a switch or node in the architecture
# in the form of {type}{count}. See defaults.
# Add and remove items based on how many items you would like
# at each layer. Name must end in a single digit number.
# This limits each layer to at most ten entities.

SPINES="spine0 spine1"
LEAVES="leaf0 leaf1"
NODES="node0 node1"


SWMEM=1024
SWCPU=1
NODEMEM=1024
NODECPU=1

# Don't change these
PORTS="$(echo {0..5})"
UPLINK=(4 5)
SWITCHES="vqfx vqfx-pfe"
declare -A SWIMAGES
SWIMAGES=( ['vqfx']=$VQFXRE ['vqfx-pfe']=$VQFXPFE)
declare -A UDPPRE
UDPPRE=( ['spine']=1 ['leaf']=2 )

