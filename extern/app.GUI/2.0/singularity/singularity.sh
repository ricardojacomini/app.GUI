#!/bin/bash
# -*- coding: utf-8 -*-
# Script for binding libraries into Singularity container
# The Advanced Research Computing at Hopkins (ARCH)
# Ricardo S Jacomini < rdesouz4 @ jhu.edu >
# Date: Feb, 22 2024
unset SBIND

for i in $(ldconfig -p | grep -E "/libib|/libgpfs|/libnuma|/libmlx|/libnl|/libsensor|/libtinfo|/libcpupower" | awk '{print $4}'); do
    # Check if the path starts with "/lib64"
    if [[ $i == /lib64* && -f "$i" ]]; then
        if [ -z "${SBIND:-}" ]; then
            SBIND="$i"
        else
            SBIND="$SBIND,$i"
        fi
    fi
done

if [ -z "${SBIND:-}" ]; then
    echo -e "Could not find any IB-related libraries on this host!\n";
else
    export SINGULARITY_BIND=$SINGULARITY_BIND,$SBIND,'/usr/bin/csh/'
fi

# echo "SBIND=$SBIND"

