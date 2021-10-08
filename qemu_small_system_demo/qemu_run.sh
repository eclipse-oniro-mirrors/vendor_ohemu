#!/bin/bash

#Copyright (c) 2020-2021 Huawei Device Co., Ltd.
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

#set -e
flash_name=flash.img
rebuild=no
net_enable=no
vnc="-vnc :20  -serial mon:stdio"
src_dir=out/arm_virt/qemu_small_system_demo/
re_arg=no
bootargs=$(cat <<-END
bootargs=root=cfi-flash fstype=jffs2 rootaddr=10M rootsize=22M useraddr=32M usersize=32M
END
)
help_info=$(cat <<-END
Usage: qemu-run [OPTION]...
Make a qemu image($flash_name) for OHOS, and run the image in qemu according
to the options.

    Options:

    -f, --force                rebuild ${flash_name}
    -n, --net-enable           enable net
    -l, --local-desktop        no VNC
    -b, --bootargs             additional boot arguments(-bk1=v1,k2=v2...)
    -h, --help                 print help info

    By default, ${flash_name} will not be rebuilt if exists, and net will not
    be enabled, gpu enabled and waiting for VNC connection at port 5920.
END
)

function make_flash(){
    echo -e "\nStart making ${flash_name}..."
    echo -ne "${bootargs}"'\0' > ${src_dir}/bootargs
    dd if=/dev/zero of=${flash_name} bs=64M count=1
    dd if=${src_dir}/OHOS_Image.bin of=${flash_name} conv=notrunc seek=0 oflag=seek_bytes
    dd if=${src_dir}/bootargs of=${flash_name} conv=notrunc seek=9984k oflag=seek_bytes
    dd if=${src_dir}/rootfs_jffs2.img of=${flash_name} conv=notrunc seek=10M oflag=seek_bytes
    dd if=${src_dir}/userfs_jffs2.img of=${flash_name} conv=notrunc seek=32M oflag=seek_bytes
    echo -e "Success making ${flash_name}...\n"
}

function net_config(){
    echo "Network config..."
    sudo modprobe tun tap
    sudo ip link add br0 type bridge
    sudo ip address add 10.0.2.2/24 dev br0
    sudo ip link set dev br0 up
}

function start_qemu(){
    net_enable=${1}
    read -t 5 -p "Enter to start qemu[y/n]:" flag
    start=${flag:-y}
    if [[ "${vnc}" == "-vnc "* ]]; then
        echo -e "Waiting VNC connection on: 5920 ...(Ctrl-C exit)"
    fi
    if [ ${start} = y ]; then
        if [ ${net_enable} = yes ]
        then
            net_config 2>/dev/null
            sudo `which qemu-system-arm` -M virt,gic-version=2,secure=on -cpu cortex-a7 -smp cpus=1 -m 1G -drive \
            if=pflash,file=./${flash_name},format=raw -global virtio-mmio.force-legacy=false -netdev bridge,id=net0 \
            -device virtio-net-device,netdev=net0,mac=12:22:33:44:55:66 \
            -device virtio-gpu-device,xres=800,yres=480 -device virtio-mouse-device ${vnc}
        else
            `which qemu-system-arm` -M virt,gic-version=2,secure=on -cpu cortex-a7 -smp cpus=1 -m 1G -drive \
            if=pflash,file=./${flash_name},format=raw -global virtio-mmio.force-legacy=false \
            -device virtio-gpu-device,xres=800,yres=480 -device virtio-mouse-device ${vnc}
        fi
    else
        echo "Exit qemu-run"
    fi
}

############################## main ##############################
ARGS=`getopt -o fnlb:h -l force,net-enable,local-desktop,bootargs:,help -n "$0" -- "$@"`
if [ $? != 0 ]; then
    echo "Try '$0 --help' for more information."
    exit 1
fi
eval set --"${ARGS}"

while true;do
    case "${1}" in
        -f|--force)
        shift;
        rebuild=yes
        echo -e "Redo making ${flash_name}..."
        ;;
        -n|--net-enable)
        shift;
        net_enable=yes
        echo -e "Qemu net enable..."
        ;;
        -l|--local-desktop)
        shift;
        vnc=""
        ;;
        -b|--bootargs)
        shift;
        re_arg=yes
        bootargs+=" "${1//","/" "}
        shift
        ;;
        -h|--help)
        shift;
        echo -e "${help_info}"
        exit
        ;;
        --)
        shift;
        break;
        ;;
    esac
done

if [ ! -f "${flash_name}" ] || [ ${rebuild} = yes ]; then
    make_flash ${flash_name} "${bootargs}" ${src_dir}
elif [ ${re_arg} = yes ]; then
    echo "Update bootargs..."
    echo -e "${bootargs}"'\0' > ${src_dir}/bootargs
    dd if=${src_dir}/bootargs of=${flash_name} conv=notrunc seek=9984k oflag=seek_bytes
fi
start_qemu ${net_enable}
