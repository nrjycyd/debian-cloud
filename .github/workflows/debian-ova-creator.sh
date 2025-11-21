#!/bin/bash

# 默认参数
debver=""
debarch="amd64"
cpu_count=2
mem_size=1024
disk_size=10
disk_type="scsi"        # scsi / ide
disk_format="vmdk"      # OVF 内的 disk format
network_type="vmxnet3"  # e1000 / vmxnet3

show_help() {
    cat << EOF
Usage: $0 [options]

Options:
  -d <debian_version>  Debian version (required)
  -c <cpu_count>       Number of virtual CPUs (default: 2)
  -m <memory_mb>       Memory size in MB (default: 1024)
  -s <disk_gb>         Disk size in GB (default: 10)
  --disk-type <type>   Disk controller type: scsi or ide (default: scsi)
  --network-type <type> Network adapter: vmxnet3 or e1000 (default: vmxnet3)
  -h                   Show this help message

Example:
  $0 -d 13 -c 4 -m 4096 -s 20 --disk-type scsi --network-type vmxnet3
EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -d) debver="$2"; shift 2 ;;
        -c) cpu_count="$2"; shift 2 ;;
        -m) mem_size="$2"; shift 2 ;;
        -s) disk_size="$2"; shift 2 ;;
        --disk-type) disk_type="$2"; shift 2 ;;
        --network-type) network_type="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [[ -z "$debver" ]]; then
    echo "Error: Debian version is required"
    show_help
    exit 1
fi

# Debian版本映射
case "$debver" in
    11|bullseye) debver="11"; debcodename="bullseye" ;;
    12|bookworm) debver="12"; debcodename="bookworm" ;;
    13|trixie) debver="13"; debcodename="trixie" ;;
    sid) debver="sid"; debcodename="sid/daily"; debarch="amd64-daily" ;;
    *) echo "Error: Unsupported version $debver"; exit 1 ;;
esac

DEBIAN_VERSION=${debver}
DEBIAN_NAME=${debcodename}
DEBIAN_ARCH=${debarch}

VIRTUAL_SYSTEM_TYPE=vmx-19
OVF_OS_ID=96
OVF_OS_TYPE=debian11_64Guest
CURRENT_DATE=$(date +%Y%m%d)

FILE_NAME=debian-$DEBIAN_VERSION-genericcloud-$DEBIAN_ARCH
FILE_ORIG_EXT=qcow2
FILE_DEST_EXT=vmdk
FILE_SIGN_EXT=mf
FILE_ORIG_URL=https://cdimage.debian.org/images/cloud/$DEBIAN_NAME/latest/$FILE_NAME.$FILE_ORIG_EXT

# 下载 QCOW2
if [ ! -f "$FILE_NAME.$FILE_ORIG_EXT" ]; then
    wget "$FILE_ORIG_URL"
else
    echo "The file $FILE_NAME.$FILE_ORIG_EXT was already downloaded"
fi

# 转 VMDK
if [ ! -f "$FILE_NAME.$FILE_DEST_EXT" ]; then
    qemu-img convert -f $FILE_ORIG_EXT -O $FILE_DEST_EXT -o subformat=streamOptimized "$FILE_NAME.$FILE_ORIG_EXT" "$FILE_NAME.$FILE_DEST_EXT"
else
    echo "The file $FILE_NAME.$FILE_DEST_EXT was already created"
fi

FILE_DEST_SIZE=$(wc -c "$FILE_NAME.$FILE_DEST_EXT" | cut -d " " -f1)

# 根据控制器类型选择 OVF ID
if [[ "$disk_type" == "ide" ]]; then
    disk_controller_type="5" # IDE Controller
else
    disk_controller_type="6" # SCSI Controller
fi

# 网卡类型 OVF 映射
if [[ "$network_type" == "vmxnet3" ]]; then
    net_subtype="VmxNet3"
else
    net_subtype="e1000"
fi

# 生成 OVF 文件
cat <<EOF | tee "$FILE_NAME.ovf" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1">
  <References>
    <File ovf:href="$FILE_NAME.$FILE_DEST_EXT" ovf:id="file1" ovf:size="$FILE_DEST_SIZE"/>
  </References>

  <DiskSection>
    <Disk ovf:capacity="$((disk_size*1024*1024*1024))" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>

  <NetworkSection>
    <Network ovf:name="VM Network"/>
  </NetworkSection>

  <VirtualSystem ovf:id="$FILE_NAME-$CURRENT_DATE">
    <OperatingSystemSection ovf:id="$OVF_OS_ID" vmw:osType="$OVF_OS_TYPE">
      <Description>Debian GNU/Linux $DEBIAN_VERSION (64-bit)</Description>
    </OperatingSystemSection>

    <VirtualHardwareSection ovf:transport="iso">
      <System>
        <vssd:VirtualSystemType>$VIRTUAL_SYSTEM_TYPE</vssd:VirtualSystemType>
      </System>

      <Item>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>$cpu_count</rasd:VirtualQuantity>
      </Item>

      <Item>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>$mem_size</rasd:VirtualQuantity>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
      </Item>

      <Item>
        <rasd:ResourceType>$disk_controller_type</rasd:ResourceType>
        <rasd:ElementName>${disk_type^} Controller 0</rasd:ElementName>
      </Item>

      <Item>
        <rasd:ResourceType>17</rasd:ResourceType>
        <rasd:Parent>3</rasd:Parent>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
      </Item>

      <Item>
        <rasd:ResourceType>10</rasd:ResourceType>
        <rasd:ResourceSubType>$net_subtype</rasd:ResourceSubType>
        <rasd:Connection>VM Network</rasd:Connection>
      </Item>

    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF

# 生成 MF 文件
FILE_DEST_SUM=$(sha256sum "$FILE_NAME.$FILE_DEST_EXT" | cut -d " " -f1)
FILE_OVF_SUM=$(sha256sum "$FILE_NAME.ovf" | cut -d " " -f1)
cat <<EOF | tee "$FILE_NAME.$FILE_SIGN_EXT" > /dev/null
SHA256($FILE_NAME.$FILE_DEST_EXT)= $FILE_DEST_SUM
SHA256($FILE_NAME.ovf)= $FILE_OVF_SUM
EOF

# 打包 OVA
tar -vcf "$FILE_NAME.ova" \
         "$FILE_NAME.ovf" \
         "$FILE_NAME.$FILE_SIGN_EXT" \
         "$FILE_NAME.$FILE_DEST_EXT"
