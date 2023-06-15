#!/bin/bash
# AUTHOR:	Dr. Alistair Ward
# DESCRIPTION:	Part of <https://functionalley.com/Storage/flashback.html>, where there's documentation for this executable.
#		Creates an encrypted LUKS storage-volume using an interactively specified passphrase.
#		Creates a Btrfs filesystem using the specified checksum-algorithm.
#		The filesystem is then unmounted & the storage-volume encrypted.
# CAVEATS:	Creation of backups & snapshots falls outside the remit of this script.
#		The encryption-passphrase must be entered several times.
# EXAMPLE:	formatForBackup.bash -v '/dev/sdb';

declare		VERBOSE=''
declare		NAME_DECRYPTED_STORAGE_VOLUME='decrypted'
declare		LABEL_FILESYSTEM='Backup'
declare		ALGORITHM_CHECKSUM='blake2'	# See 'man -s5 btrfs' for options.
declare		NAME_USER="${LOGNAME:-$(id --real --user --name)}"	# The current user's name.
declare		NAME_GROUP=$(id --real --group --name)	# The current user's default group.
declare		DIR_MOUNTPOINT="/tmp/$LABEL_FILESYSTEM"
declare -r	PATH_PREFIX_DEVICE='/dev'

# Operate on the decrypted filesystem.
operateOnFilesystem (){
	local -i	RETURN_CODE=0
	local -r	OWNER="$NAME_USER:$NAME_GROUP"

# Whilst this filesystem was created by root, the owner can be less privileged.
	if ! sudo chown $VERBOSE -- "$OWNER" "$DIR_MOUNTPOINT"; then
		echo "'chown $OWNER $DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=1
	fi

	return $RETURN_CODE;
}

# Create a new filesystem, mount it, then operate on it.
operateOnStorageVolume (){
	local -i	RETURN_CODE
	local -r	DECRYPTED_DEVICE="$PATH_PREFIX_DEVICE/mapper/$NAME_DECRYPTED_STORAGE_VOLUME"

	if [[ ! -b "$DECRYPTED_DEVICE" ]]; then
		echo "Block-device '$DECRYPTED_DEVICE' not found" >&2

		RETURN_CODE=2
	elif ! sudo -- $MKFS_BTRFS --csum="$ALGORITHM_CHECKSUM" --label="$LABEL_FILESYSTEM" -- "$DECRYPTED_DEVICE"; then	# Create & label a file-system on the storage-volume, referencing the newly mapped device-name.
		echo "'$MKFS_BTRFS --csum=$ALGORITHM_CHECKSUM --label=$LABEL_FILESYSTEM $DECRYPTED_DEVICE' failed" >&2

		RETURN_CODE=3
	elif [[ ! -d "$DIR_MOUNTPOINT" ]] && ! mkdir $VERBOSE -- "$DIR_MOUNTPOINT"; then	# Create a mount-point of arbitrary path.
		echo "'mkdir $DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=4
	elif ! sudo mount $VERBOSE -- "$DECRYPTED_DEVICE" "$DIR_MOUNTPOINT"; then	# Mount the decrypted storage-volume.
		echo "'mount $DECRYPTED_DEVICE $DIR_MOUNTPOINT' failed" >&2

		RETURN_CODE=5
	else
		operateOnFilesystem

		RETURN_CODE=$?

# Unmount the decrypted storage-volume.
		if ! sudo umount $VERBOSE -- "$DIR_MOUNTPOINT"; then
			echo "'umount $DIR_MOUNTPOINT' failed" >&2

			(( RETURN_CODE == 0 )) && RETURN_CODE=6
		fi
	fi

	return $RETURN_CODE;
}

# Define the encryption, open & decrypt the storage-volume, then operate on it.
operateOnBlockDevice (){
	local -i	RETURN_CODE
	local -r	TYPE_STORAGE_VOLUME='luks2'

	if [[ ! -b "$BLOCK_DEVICE_NAME" ]]; then
		echo "Block-device='$BLOCK_DEVICE_NAME' not found" >&2

		RETURN_CODE=7
	elif ! sudo -- $CRYPTSETUP $VERBOSE --verify-passphrase --type="$TYPE_STORAGE_VOLUME" luksFormat "$BLOCK_DEVICE_NAME"; then	# Create a storage-volume on the device.
		echo "'$CRYPTSETUP luksFormat $BLOCK_DEVICE_NAME' failed" >&2

		RETURN_CODE=8
	elif ! sudo -- $CRYPTSETUP $VERBOSE open --type="$TYPE_STORAGE_VOLUME" "$BLOCK_DEVICE_NAME" "$NAME_DECRYPTED_STORAGE_VOLUME"; then	# Define the symmetrical encryption passphrase & map the decrypted storage-volume to a device-name.
		echo "'$CRYPTSETUP open $BLOCK_DEVICE_NAME $NAME_DECRYPTED_STORAGE_VOLUME' failed" >&2

		RETURN_CODE=9
	else
		operateOnStorageVolume

		RETURN_CODE=$?

# Close the mapped device.
		if ! sudo -- $CRYPTSETUP $VERBOSE close "$NAME_DECRYPTED_STORAGE_VOLUME"; then
			echo "'$CRYPTSETUP close $NAME_DECRYPTED_STORAGE_VOLUME' failed" >&2

			(( RETURN_CODE == 0 )) && RETURN_CODE=10
		elif [[ ! -z "$VERBOSE" ]]; then
			echo "Device '$BLOCK_DEVICE_NAME' can now be safely removed."
		fi
	fi

	return $RETURN_CODE;
}

declare -i	EXIT_STATUS=0

if (( $(id --user) == 0 )); then
	echo 'This script was not designed to be run by root' >&2

	EXIT_STATUS=-1
else
	while getopts 'vd:f:c:u:g:' OPTION; do
		case "$OPTION" in
			v) VERBOSE='--verbose' ;;
			d) NAME_DECRYPTED_STORAGE_VOLUME="$OPTARG" ;;
			f) LABEL_FILESYSTEM="$OPTARG" ;;
			c) ALGORITHM_CHECKSUM="$OPTARG" ;;
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

			if ! sudo --validate; then
				echo '"sudo --validate" failed' >&2
			else

# Check that the required executables exist.
				declare -r	CRYPTSETUP=$(sudo which cryptsetup)
				declare -r	MKFS_BTRFS=$(sudo which mkfs.btrfs)

				if [[ -z "$CRYPTSETUP" || -z "$MKFS_BTRFS" ]]; then
					echo 'Executable not found' >&2

					EXIT_STATUS=-4
				else
					operateOnBlockDevice

					EXIT_STATUS=$?
				fi
			fi
		fi
	fi
fi

exit $EXIT_STATUS

