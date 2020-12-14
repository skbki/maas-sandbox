#!/usr/bin/env bash

set -xe

# $1: MAAS_IP
# $2: OAM_DYNAMIC_RANGE_START
# $3: OAM_DYNAMIC_RANGE_END
# $4: OAM_RESERVED_RANGE_START
# $5: OAM_RESERVED_RANGE_END
# $6: HOST_USERNAME
# $7: HOST_IP
# $8: OAM_NETWORK_PREFIX
# $9: CLOUD_NODES_COUNT
# $10: LOCAL_IMAGE_MIRROR_URL
# $11: MAAS_ZONES_COUNT
# $12: MGMT_NODES_COUNT


# Initialize MAAS
echo "Initializing MAAS..."
if ! (maas apikey --username root > /dev/null 2>&1)
then
    maas init region+rack --database-uri maas-test-db:/// --maas-url http://localhost:5240/MAAS/
    maas createadmin --username admin --password admin --email admin@example.com --ssh-import gh:skbki
else
    echo "MAAS already initialized, skipping"
fi

# Wait until MAAS endpoint URL is available
while nc -z localhost 5240 ; [ $? -ne 0 ] 
do
    echo "MAAS endpoint URL is not available yet, waiting 10s..."
    sleep 10
done

# Log into MAAS
echo "Logging into MAAS..."
maas login root http://localhost:5240/MAAS $(maas apikey --username admin)

# Use local image mirror, if configured
if [ ! -z ${10} ]
then
    echo "Requesting MAAS to stop importing images before updating" \
         "boot-source with local image mirror URL..."
    maas root boot-resources stop-import

    while [ $(maas root boot-resources is-importing) != "false" ]
    do 
        echo "MAAS is still importing images. Requesting MAAS to stop" \
             "importing images (again) and waiting 30s..."
        maas root boot-resources stop-import
        sleep 30
    done
    
    echo "Updating boot-source to point to local image mirror..."
    maas root boot-source update 1 url="${10}"
fi

# Start importing images
echo "Requesting MAAS to import images..."
maas root boot-resources import

# Import local SSH key to MAAS, if not already imported
echo "Importing SSH key..."
if ! (maas root sshkeys read | grep "$(</home/vagrant/.ssh/id_rsa.pub)")
then
    maas root sshkeys create "key=$(</home/vagrant/.ssh/id_rsa.pub)"
else
    echo "SSH key already imported, skipping"
fi

# Skip intro
echo "Configuring 'completed_intro'..."
maas root maas set-config name=completed_intro value=true

# Create reserved dynamic range for OAM network (if it does not exist already)
echo "Creating dynamic range..."
RESULT=$(maas root ipranges read | \
    jq ".[] | select((.type==\"dynamic\") and (.start_ip==\"$2\") and (.end_ip==\"$3\")) | .id")
if [ -z ${RESULT} ]
then
    maas root ipranges create type=dynamic start_ip=$2 end_ip=$3
else
    echo "Dynamic range already created, skipping"
fi

# Create reserved range for MAAS server and networking equipment
echo "Creating reserved range..."
RESULT=$(maas root ipranges read | \
    jq ".[] | select((.type==\"reserved\") and (.start_ip==\"$4\") and (.end_ip==\"$5\")) | .id")
if [ -z ${RESULT} ]
then
    maas root ipranges create type=reserved start_ip=$4 end_ip=$5
else
    echo "Reserved range already created, skipping"
fi

# Provide DHCP for OAM network subnet
echo "Configuring DHCP for OAM network..."
FABRIC_ID=$(maas root subnet read ${8}0/24 | jq '.vlan | .fabric_id')
maas root vlan update $FABRIC_ID untagged primary_rack=maas dhcp_on=True

# Configure default gateway for OAM network
echo "Configuring gateway for OAM network..."
maas root subnet update ${8}0/24 gateway_ip=${8}1

# Disable 'Automatically sync images'
echo "Disabling 'Automatically sync images'..."
maas root maas set-config name=boot_images_auto_import value=false

# Wait until MAAS finished importing images
echo "Waiting for MAAS to finish importing images..."
while [ $(maas root boot-resources is-importing) != "false" ]
do 
    echo "MAAS is still importing images, waiting 10s..."
    sleep 10
done

# Wait until Rack Controller finishes syncing images
echo "Waiting for Rack Controller to finish synchronizing the images "; 
RACK_CONTROLLER_ID=$(maas root region-controllers read | \
    jq --raw-output '.[] | .system_id')
while [ $(maas root rack-controller list-boot-images $RACK_CONTROLLER_ID | \
    jq --raw-output '.status') != "synced" ]
do 
    echo "MAAS Rack is still synchronizing images, waiting 10s..."
    sleep 10
done

# Configuring default image
echo "Configuring default image"
maas root maas set-config name=default_min_hwe_kernel value=hwe-20.04-lowlatency

# Create nodeNN nodes
echo "Creating cloud machines..."
for i in $(seq 1 ${9})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=node${NODE_NUM} | jq '.[] | .system_id')

    if [ -z ${MACHINE} ]
    then
        maas root machines create \
            architecture="amd64/generic" \
            mac_addresses="0e:00:00:00:00:${NODE_NUM}" \
            hostname=node${NODE_NUM} \
            power_type=virsh power_parameters='{"power_address": "qemu+ssh://'${6}'@'${7}'/system", "power_id": "node'${NODE_NUM}'"}'
    else
        echo "Machine node${NODE_NUM} already exists, skipping"
    fi
done

# Create mgmtnodeNN nodes
echo "Creating cloud machines..."
for i in $(seq 1 ${12})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=mgmtnode${NODE_NUM} | jq '.[] | .system_id')

    if [ -z ${MACHINE} ]
    then
        maas root machines create \
            architecture="amd64/generic" \
            mac_addresses="0e:00:00:00:01:${NODE_NUM}" \
            hostname=mgmtnode${NODE_NUM} \
            power_type=virsh power_parameters='{"power_address": "qemu+ssh://'${6}'@'${7}'/system", "power_id": "mgmtnode'${NODE_NUM}'"}'
    else
        echo "Machine mgmtnode${NODE_NUM} already exists, skipping"
    fi
done

# Create tags
echo "Creating tags..."
echo "Juju..."
maas root tags create name=juju

echo "Compute..."
maas root tags create name=compute

echo "ceph-osd..."
maas root tags create name=ceph-osd




# Assigning juju tag to nodes
echo "Assigning juju tag to nodes..."
for i in $(seq 1 ${12})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=mgmtnode$NODE_NUM | jq '.[] | .system_id')

    if [ ! -z ${MACHINE} ]
    then
        maas root tag update-nodes juju add=$MACHINE
    else
        echo "Tag already exists or something went wrong!"
    fi
done


# Assigning ceph and computetags to rest of nodes
echo "Assigning ceph and computetags to rest of nodes..."
for i in $(seq 1 ${9})
do
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=node${NODE_NUM} | jq '.[] | .system_id')
    maas root tag update-nodes compute add=$MACHINE
    maas root tag update-nodes ceph-osd add=$MACHINE
done

# Create zones
echo "Creating zone AZ-1..."
maas root zones create name=AZ-1 description=AZ-1
echo "Creating zone AZ-2..."
maas root zones create name=AZ-2 description=AZ-2
echo "Creating zone AZ-3..."
maas root zones create name=AZ-3 description=AZ-3

# Create reserved range for MAAS server and networking equipment
echo "Creating reserved range..."

if [ ${$12} -gt 0 ]
then
    maas root ipranges create type=reserved start_ip=$4 end_ip=$5
else
    echo "Reserved range already created, skipping"
fi


# # Create zones
# echo "Creating zones..."
# for i in $(seq 1 ${11})
# do
#     # Check if the zone exists
#     ZONE_NUM=${i}
#     MACHINE=$(maas root machines read hostname=node${NODE_NUM} | jq '.[] | .system_id')

#     if [ ! -z ${MACHINE} ]
#     then
#         maas root machines create \
#             architecture="amd64/generic" \
#             mac_addresses="0e:00:00:00:00:${NODE_NUM}" \
#             hostname=node${NODE_NUM} \
#             power_type=virsh power_parameters='{"power_address": "qemu+ssh://'${6}'@'${7}'/system", "power_id": "node'${NODE_NUM}'"}'
#     else
#         echo "Machine node${NODE_NUM} already exists, skipping"
#     fi
# done

# Reset power of the machines so that they can start commissioning
echo "Power cycling machines..."
for i in $(seq 1 ${9})
do
    # Check if the machine exists
    NODE_NUM=$(printf %02d ${i})
    MACHINE=$(maas root machines read hostname=node${NODE_NUM} | \
        jq --raw-output '.[] | .system_id')

    if [ ! -z ${MACHINE} ]
    then
        # Query machine status
        MACHINE_STATUS=$(maas root machine read ${MACHINE} | \
            jq --raw-output '.status_name')

        # Skip commissioning if the machine is already commissioned and
        # in 'Ready' state
        if [ ${MACHINE_STATUS} == "Ready" ]
        then
            echo "Machine \'node${NODE_NUM}\' (${MACHINE}) is already" \
                 "commissioned, skipping..."
            continue
        fi

        if [ ${MACHINE_STATUS} == "Commissioning" ]
        then
            # Abort automatic commissioning after the node has been created
            maas root machine abort ${MACHINE}
        fi

        # Query power state
        POWER_STATE=$(maas root machine query-power-state ${MACHINE} | \
            jq --raw-output '.state')

        # Power off the machine if it is on
        while [ ${POWER_STATE} != "off" ]
        do
            echo "Powering off machine \'node${NODE_NUM}\' (${MACHINE})"
            maas root machine power-off ${MACHINE}

            POWER_STATE=$(maas root machine query-power-state ${MACHINE} | \
                jq --raw-output '.state')
        done

        echo "Requesting commissioning of the machine \'node${NODE_NUM}\' (${MACHINE})"
        maas root machine commission ${MACHINE}
    else
        echo "WARNING: Machine node${NODE_NUM} does not exist, skipping"
    fi
done