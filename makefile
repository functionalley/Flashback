# AUTHOR:	Dr. Alistair Ward
# DESCRIPTION:	Part of <https://functionalley.com/Storage/flashback.html>.
# CAVEAT:	The value of DIR_MASTER may need to be changed to the directory under which your personal files are stored.

.PHONY: backup cullSnapshots scrub zero

SHELL		:= /bin/bash
.DEFAULT_GOAL	:= backup
DIR_BACKUP	:= Documents
DIR_SNAPSHOTS	:= .snapshots
FILE_EXCLUSIONS	:= exclusions.txt
TIME_FORMAT	:= %Y-%m-%dT%H-%M-%S
DIR_MASTER	:= ~/$(DIR_BACKUP)
MAX_SNAPSHOTS	:= 7
VERBOSE		:= --verbose

$(FILE_EXCLUSIONS):
	>$(FILE_EXCLUSIONS);	# Create an empty file.

$(DIR_BACKUP) $(DIR_SNAPSHOTS):
	sudo btrfs $(VERBOSE) subvolume create -- '$@';	# Create a subvolume.
	sudo chown $(VERBOSE) -- "$$(id --real --user --name):$$(id --real --group --name)" '$@';	# Change the owner/group.

# Create a backup.
backup: $(FILE_EXCLUSIONS) $(DIR_BACKUP) $(DIR_SNAPSHOTS)
	@[[ -d $(DIR_MASTER) ]];	# Confirm the existence of the master-directory.
	[[ -z $$(find $(DIR_MASTER)/ -xtype l) ]];	# Check for dangling symlinks, which are probably unintended & which rsync can't follow.
	@[[ -z $$(ls '$(DIR_BACKUP)') ]] || sudo btrfs $(VERBOSE) subvolume snapshot -r -- '$(DIR_BACKUP)/' $(DIR_SNAPSHOTS)/$$(date '+$(TIME_FORMAT)');	# Create a readonly snapshot.
	rsync $(VERBOSE) --archive --update --exclude-from '$(FILE_EXCLUSIONS)' --delete --copy-links -- $(DIR_MASTER)/ './$(DIR_BACKUP)/';	# Sync the backup, following symlinks.

# Delete excess snapshots, oldest first.
cullSnapshots:
	@declare -ra	SNAPSHOTS=( $$(ls -rd -- $(DIR_SNAPSHOTS)/* 2>/dev/null) );\
	declare -i	i="$${#SNAPSHOTS[@]}";\
	while (( --i >= $(MAX_SNAPSHOTS) )); do sudo btrfs $(VERBOSE) subvolume delete -- "$${SNAPSHOTS[$$i]}"; done

# Checksum the filesystem.
scrub:
	sudo btrfs $(VERBOSE) scrub start -B ./;

# Start the next backup from scratch.
zero:
	sudo btrfs subvolume list -t --sort='-rootid' ./ | sed -e '1,2d' -e 's/^.*\t//' | xargs --no-run-if-empty sudo btrfs $(VERBOSE) subvolume delete --;

