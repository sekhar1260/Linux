#!/bin/bash

. .profile

echo "Welcome to RENBE process of creating a Ubuntu 22 Template"
echo "Here is the Sequence of execution:"
echo "1) Find Ubuntu 22.10 Live ISO image"
echo "2) Unpack files to a folder : source-files"
echo "3) Add/Remove files and modify content of few files"
echo "4) Generate new autoinstall ISO"
echo "5) Copy ISO to vCenter Datastore"
echo "6) Create a VM with autoinstall ISO attached"
echo "7) PowerON - OS installs on it's own after PowerON"
echo "8) Perform Post installation tasks"
echo "9) Export to ova and place it in Share location"

extract_iso() {
    echo "Extracting ISO content:"

    # Get the parent folder by going up one level
    parent_folder="/root"
    # Define the folder presence
    if [ ! -d "$parent_folder/$extract_folder" ]; then
	cd $parent_folder
        mkdir "$extract_folder"
        echo "Folder '$extract_folder' created."
    else
        echo "Folder '$extract_folder' already exists."
    fi

    if [ -e "$GOVC_SourceDir/$source_file" ]; then
	7z -y x "$GOVC_SourceDir/$source_file"  -o"$parent_folder/$extract_folder"

        # Check the exit status of the 7z command to see if extraction was successful
        if [ $? -eq 0 ]; then
            echo "Extraction successful."
	    prepare_custom_iso

        else
            echo "Extraction failed."
	    exit 1
        fi
    else    
        echo "Ubuntu ISO '$source_file' not found in '$GOVC_SourceDir'."
        exit 1
    fi
}

prepare_custom_iso() {
    echo "Modifying the ISO content to make is autoinstall Ubuntu Image"
    cd "$parent_folder/$extract_folder"
    folder_name="[BOOT]"
    # Check if the folder exists
    if [ -d "$folder_name" ]; then
    # Move the folder and its contents recursively
        mv -f "$folder_name" "$parent_folder/BOOT"
        if [ $? -eq 0 ]; then
            echo "Folder '$folder_name' moved successfully."
        else
            echo "Failed to move folder '$folder_name'."
        fi
    else
        echo "Folder '$folder_name' not found."
    fi
  
    custom_folder="$parent_folder/RENBE/ubuntu_files/"
    # Check if the source folder and grub.cfg file exist
    if [ -d "$custom_folder" ] && [ -f "$custom_folder/grub.cfg" ]; then
    # Copy grub.cfg to the destination folder
    cp "$custom_folder/grub.cfg" "$parent_folder/$extract_folder/boot/grub"
    
        # Check the exit status of the cp command to see if the copy was successful
        if [ $? -eq 0 ]; then
            echo "grub.cfg copied successfully to '$extract_folder/boot/grub'."
        else
            echo "Failed to copy grub.cfg to '$extract_folder'."
        fi
    else
        echo "Source folder '$custom_folder' or grub.cfg file not found."
    fi  

    if [ ! -d "$parent_folder/$extract_folder/server" ]; then
        cd "$parent_folder/$extract_folder"
        mkdir "server"
        echo "Folder server created."
    else
        echo "Folder server already exists."
    fi

    if [ -f "$custom_folder/user-data" ]; then
    # Copy user-data to the destination folder
    cp "$custom_folder/user-data" "$parent_folder/$extract_folder/server"
    touch "$parent_folder/$extract_folder/server/meta-data"
    fi
   
}

vm_power_status(){
    #Check for Power status of the VM
    response=$(govc vm.info "$vm_name" | grep "Power state")
    power_state=$(echo "$response" | awk '{print $NF}')

    # Check if the power state is "poweredOn" or "poweredOff"
    if [ "$power_state" == "poweredOn" ]; then
  	echo "The VM is powered on."
	govc vm.power -off "$vm_name"
	power_op=$?
    	if [ $power_op -eq 0 ]; then
	    echo "$vm_name Poweroff successful"
        else
 	    echo "$vm_name PowerOff Operation failed"
	    exit 1
        fi	
    elif [ "$power_state" == "poweredOff" ]; then
  	echo "The VM is in Powered off state already."
    else
  	echo "Unable to determine the power state."
	exit 2
    fi
}

delete_vm() {
    # Check VM Power Status and PowerOff if required
    vm_power_status	
    # Delete VM 
    govc vm.destroy "$vm_name"
    destroy_op=$?
    if [ $destroy_op -eq 0 ]; then
        echo "$vm_name was destroyed successful"
	create_vm
    else
        echo "Failed to destroy $vm_name"
        exit 1
    fi
   
}

create_custom_iso() {
 
    autoinstall_iso="ubuntu-22.10-autoinstall.iso"
    cd "$parent_folder/$extract_folder"
    echo "You are currently in $extract_folder"
    #Create custom Image usnig xorriso
    xorriso -as mkisofs -r   -V 'Ubuntu 22.04 LTS AUTO (EFIBIOS)'   -o "$parent_folder/$autoinstall_iso"   --grub2-mbr "$parent_folder/BOOT/1-Boot-NoEmul.img"   -partition_offset 16   --mbr-force-bootable   -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$parent_folder/BOOT/2-Boot-NoEmul.img"   -appended_part_as_gpt   -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7   -c '/boot.catalog'   -b '/boot/grub/i386-pc/eltorito.img'     -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info   -eltorito-alt-boot   -e '--interval:appended_partition_2:::'   -no-emul-boot   .

}

create_vm(){
    echo "Proceeding with ISO Upload and VM Creation....."
    create_custom_iso
    govc datastore.upload -ds='ME4-CL01' "$parent_folder/$autoinstall_iso" "/$autoinstall_iso"
    sleep 5
    copy_op=$?
    if [ $copy_op -eq 0 ]; then
	echo "Copy of OS ISO successful......Proceeding with VM Creation"
    else
	echo "Copy of ISO image failed. Exiting"
    fi	

    govc vm.create -on=false -ds="ME4-CL01" -net="Cloudlink_PGN" -m=4096 -c=2 -g=ubuntu64Guest -disk=30GB -iso="$autoinstall_iso" -disk.controller=lsilogic "$vm_name" 
    if [ $? == 0 ]; then
    	govc vm.power -on "$vm_name"
	echo "Power ON VM: $vm_name"
	OS_installation
    else
	echo "Failed to create VM"
    fi

}

OS_installation() {
    # Sleep for 600 seconds (10 minutes) for OS install to complete	
    #Check for IP address of the VM
    echo "Sleep for 10 minutes(600 seconds) for OS install to complete"
    sleep 300
    echo "5 minutes complete....Sleep in progress"
    sleep 300
    echo "10 minutes complete...Sleep in progress"
    response=$(govc vm.info "$vm_name" | grep "IP address")
    vm_ip=$(echo "$response" | awk '{print $NF}')
    if [ -n "$vm_ip" ]; then
        echo "IP address is: $vm_ip for VM: $vm_name"
        export_vm 
    fi
}

export_vm() {
    
    vm_power_status
    govc export.ovf -vm "$vm_name" "$parent_folder"

}

check_vm_presence() {

    #Find presence of the VM to delete
    vm_presence=($(govc find / -type m | grep "/$vm_name$"))

    echo "$vm_presence"

    if [[ "$vm_presence" == /* ]]; then 
	 echo "VM is present. Deleting the VM before proceeding"
	 delete_vm   
    else  
	 echo "VM is not present. Proceeding with ISO upload" 
    	 create_vm 	
    fi
}

extract_iso
check_vm_presence
