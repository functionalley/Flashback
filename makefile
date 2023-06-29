# AUTHOR:	Dr. Alistair Ward
# DESCRIPTION:	Part of <https://functionalley.com/Storage/flashback.html>.
# CAVEAT:	Requires GNU Make.
# CAVEAT:	The value of DIR_MASTER may need to be changed to the directory under which your personal files are stored.

.PHONY: backup cullSnapshots scrub sync zero

SHELL		:= /bin/bash
.DEFAULT_GOAL	:= backup
DIR_BACKUP	:= Documents
DIR_SNAPSHOTS	:= .snapshots
FILE_EXCLUSIONS	:= exclusions.txt
TIME_FORMAT	:= %Y-%m-%dT%H-%M-%S
DIR_MASTER	:= ~/$(DIR_BACKUP)
MAX_SNAPSHOTS	:= 7
VERBOSE		:= --verbose
BTRFS		:= sudo btrfs $(VERBOSE)

define CONFIRM_FILESYSTEM_TYPE       =
[[ "$$(stat --file-system --format=%T ./)" == 'btrfs' ]]
endef

$(FILE_EXCLUSIONS):
	>$(FILE_EXCLUSIONS);	# Create an empty file.

$(DIR_BACKUP) $(DIR_SNAPSHOTS):
	$(CONFIRM_FILESYSTEM_TYPE);
	$(BTRFS) subvolume create -- '$@';	# Create a subvolume.
	sudo chown $(VERBOSE) -- "$$(id --real --user --name):" '$@';	# Change the owner/group.

# Create a backup.
backup: $(FILE_EXCLUSIONS) $(DIR_BACKUP) $(DIR_SNAPSHOTS)
	@[[ -d $(DIR_MASTER) ]];	# Confirm the existence of the master-directory.
	[[ -z $$(find $(DIR_MASTER)/ -xtype l) ]];	# Check for dangling symlinks, which are probably unintended & which rsync can't follow.
	@[[ -z $$(ls '$(DIR_BACKUP)') ]] || $(BTRFS) subvolume snapshot -r -- '$(DIR_BACKUP)/' $(DIR_SNAPSHOTS)/$$(date '+$(TIME_FORMAT)');	# Create a readonly snapshot.
	rsync $(VERBOSE) --archive --update --exclude-from '$(FILE_EXCLUSIONS)' --delete --copy-links -- $(DIR_MASTER)/ './$(DIR_BACKUP)/';	# Synchronise the backup with the master, following symlinks.

# Delete excess snapshots, oldest first.
cullSnapshots:
	$(CONFIRM_FILESYSTEM_TYPE);
	@declare -ra	SNAPSHOTS=( $$(ls -rd -- $(DIR_SNAPSHOTS)/* 2>/dev/null) );\
	declare -i	i="$${#SNAPSHOTS[@]}";\
	while (( --i >= $(MAX_SNAPSHOTS) )); do $(BTRFS) subvolume delete -- "$${SNAPSHOTS[$$i]}"; done

# Checksum the filesystem.
scrub:
	$(CONFIRM_FILESYSTEM_TYPE);
	$(BTRFS) scrub start -B ./;

# Sync the filesystem to the storage-device.
sync:
	$(CONFIRM_FILESYSTEM_TYPE);
	$(BTRFS) filesystem sync ./;

# Start the next backup from scratch.
zero:
	$(CONFIRM_FILESYSTEM_TYPE);
	sudo btrfs subvolume list -t --sort='-rootid' ./ | sed -e '1,2d' -e 's/^.*\t//' | xargs --no-run-if-empty $(BTRFS) subvolume delete --;

