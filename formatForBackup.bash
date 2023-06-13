#!/bin/bash
# AUTHOR:	Dr. Alistair Ward
# DESCRIPTION:	Part of <https://functionalley.com/Storage/flashback.html>.
#		Creates an encrypted LUKS storage-volume using an interactively specified passphrase.
#		Creates a Btrfs filesystem using the specified checksum-algorithm.
#		Creates subvolumes to contain the backup & snapshots, owned by the specified user/group.
#		The filesystem is then unmounted & the storage-volume encrypted.
# CAVEATS:	Creation of backups & snapshots falls outside the remit of this script.
#		The encryption-passphrase must be entered several times.
# EXAMPLE:	formatForBackup.bash -v '/dev/sdb';

declare		VERBOSE=''
declare		NAME_DECRYPTED_STORAGE_VOLUME='decrypted'
declare		LABEL_FILESYSTEM='Backup'
declare		ALGORITHM_CHECKSUM='blake2'		# See 'man -s5 btrfs' for options.
declare		SUBVOLUME_BACKUP='Documents'
declare		SUBVOLUME_SNAPSHOTS='.snapshots'
declare		NAME_USER="${LOGNAME:-$(id --real --user --name)}"	# The current user's name.
declare		NAME_GROUP=$(id --real --group --name)	# The current user's default group.
declare		DIR_MOUNTPOINT="/tmp/$LABEL_FILESYSTEM"
declare -r	TYPE_STORAGE_VOLUME='luks2'
declare -r	PATH_PREFIX_DEVICE='/dev'
declare -i	EXIT_STATUS=0

# Create the required subvolumes.
operateOnDirectory (){
	local -i	RETURN_CODE=0
	local -r	OWNER="$NAME_USER:$NAME_GROUP"

	for S in $SUBVOLUME_BACKUP $SUBVOLUME_SNAPSHOTS; do
		if ! sudo btrfs $VERBOSE subvolume create "$S"; then
			echo "'btrfs subvolume create $S' failed" >&2

			RETURN_CODE=1

			break;
		fi
	done

# Whilst these directories/subvolumes were created by root, the owner can be less privileged.
	if (( RETURN_CODE == 0 )) && ! sudo chown $VERBOSE -R -- "$OWNER" './'; then
		echo "'chown -R $OWNER ./' failed" >&2

		RETURN_CODE=2
	fi

	return $RETURN_CODE;
}

# Move into the mounted filesystem, then operate on the empty top-level directory.
operateOnFilesystem (){
	local -i	RETURN_CODE

	if ! cd "$DIR_MOUNTPOINT"; then
		echo "cd '$DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=3
	else
		operateOnDirectory

		RETURN_CODE=$?

		cd - >/dev/null	# Exit the mounted directory.
	fi

	return $RETURN_CODE;
}

# Create a new filesystem, mount it, then operate on it.
operateOnStorageVolume (){
	local -i	RETURN_CODE
	local -r	DECRYPTED_DEVICE="$PATH_PREFIX_DEVICE/mapper/$NAME_DECRYPTED_STORAGE_VOLUME"

	if [[ ! -b "$DECRYPTED_DEVICE" ]]; then
		echo "Block-device '$DECRYPTED_DEVICE' not found" >&2

		RETURN_CODE=4
	elif ! sudo mkfs.btrfs --csum="$ALGORITHM_CHECKSUM" --label="$LABEL_FILESYSTEM" -- "$DECRYPTED_DEVICE"; then	# Create & label a file-system on the storage-volume, referencing the newly mapped device-name.
		echo "'mkfs.btrfs --csum=$ALGORITHM_CHECKSUM --label=$LABEL_FILESYSTEM $DECRYPTED_DEVICE' failed" >&2

		RETURN_CODE=5
	elif [[ ! -d "$DIR_MOUNTPOINT" ]] && ! mkdir $VERBOSE -- "$DIR_MOUNTPOINT"; then	# Create a mount-point of arbitrary path.
		echo "'mkdir $DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=6
	elif ! sudo mount $VERBOSE -- "$DECRYPTED_DEVICE" "$DIR_MOUNTPOINT"; then	# Mount the decrypted storage-volume.
		echo "'mount $DECRYPTED_DEVICE $DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=7
	else
		operateOnFilesystem

		RETURN_CODE=$?

# Unmount the decrypted storage-volume.
		if ! sudo umount $VERBOSE -- "$DIR_MOUNTPOINT"; then
			echo "'umount $DIR_MOUNTPOINT' failed" >&2

			(( RETURN_CODE == 0 )) && RETURN_CODE=8
		fi
	fi

	return $RETURN_CODE;
}

# Define the encryption, open the encrypted storage-volume, then operate on it.
operateOnBlockDevice (){
	local -i	RETURN_CODE

	if [[ ! -b "$BLOCK_DEVICE_NAME" ]]; then
		echo "Block-device='$BLOCK_DEVICE_NAME' not found" >&2

		RETURN_CODE=9
	elif ! sudo cryptsetup $VERBOSE --verify-passphrase --type="$TYPE_STORAGE_VOLUME" luksFormat "$BLOCK_DEVICE_NAME"; then	# Create a storage-volume on the device.
		echo "'cryptsetup luksFormat $BLOCK_DEVICE_NAME' failed" >&2

		RETURN_CODE=10
	elif ! sudo cryptsetup $VERBOSE open --type="$TYPE_STORAGE_VOLUME" "$BLOCK_DEVICE_NAME" "$NAME_DECRYPTED_STORAGE_VOLUME"; then	# Define the passphrase for encryption & give the decrypted storage-volume a new device-name.
		echo "'cryptsetup open $BLOCK_DEVICE_NAME $NAME_DECRYPTED_STORAGE_VOLUME' failed" >&2

		RETURN_CODE=11
	else
		operateOnStorageVolume

		RETURN_CODE=$?

# Close the mapped device.
		if ! sudo cryptsetup $VERBOSE close "$NAME_DECRYPTED_STORAGE_VOLUME"; then
			echo "'cryptsetup close $NAME_DECRYPTED_STORAGE_VOLUME' failed" >&2

			(( RETURN_CODE == 0 )) && RETURN_CODE=12
		fi
	fi

	return $RETURN_CODE;
}

if (( $(id --user) == 0 )); then
	echo 'This script was not designed to be run by the root user' >&2

	EXIT_STATUS=-1
else
	while getopts 'vd:f:c:b:s:u:g:' OPTION; do
		case "$OPTION" in
			v) VERBOSE='--verbose' ;;
			d) NAME_DECRYPTED_STORAGE_VOLUME="$OPTARG" ;;
			f) LABEL_FILESYSTEM="$OPTARG" ;;
			c) ALGORITHM_CHECKSUM="$OPTARG" ;;
			b) SUBVOLUME_BACKUP="$OPTARG" ;;
			s) SUBVOLUME_SNAPSHOTS="$OPTARG" ;;
			u) NAME_USER="$OPTARG" ;;
			g) NAME_GROUP="$OPTARG" ;;
			?)
				echo "Usage: $(basename $0)" 

				printf '\t%-32s # %s.\n'\
					'[-v]'\
					'Verbose output'\
					'[-d <name of decrypted device>]'\
					"Define the device-name to which the decrypted storage-volume is temporarily mapped. Default '$NAME_DECRYPTED_STORAGE_VOLUME'"\
					'[-f <filesystem-label>]'\
					"Define the label for the new filesystem. Default '$LABEL_FILESYSTEM'"\
					'[-c <checksum-algorithm>]'\
					"Define the checksum-algorithm used by the new filesystem. Default '$ALGORITHM_CHECKSUM'"\
					'[-b <location of backup>]'\
					"The name of the subvolume under which the backup will be stored. Default '$SUBVOLUME_BACKUP'"\
					'[-s <location of snapshots>]'\
					"The name of the subvolume under which snapshots will be stored. Default '$SUBVOLUME_SNAPSHOTS'"\
					'[-u <user-name>]'\
					"Define the owner of the subvolumes. Default '$NAME_USER'"\
					'[-g <group-name>]'\
					"Define the group of the subvolumes. Default '$NAME_GROUP'"\
					'<name of block-device/partition>'\
					'CAVEAT: to be overwritten'

				EXIT_STATUS=-2

				break

				;;
		esac
	done

	if (( $EXIT_STATUS == 0 )); then
		shift $(( $OPTIND - 1 ))	# Discard the processed command-line options.

		if [[ -z $1 ]]; then
			echo 'A device-name must be specified' >&2

			EXIT_STATUS=-3
		else
			declare -r	BLOCK_DEVICE_NAME="$PATH_PREFIX_DEVICE/${1#$PATH_PREFIX_DEVICE/}"

			operateOnBlockDevice

			EXIT_STATUS=$?
		fi
	fi
fi

exit $EXIT_STATUS

