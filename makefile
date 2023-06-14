# AUTHOR:       Dr. Alistair Ward
# DESCRIPTION:	Part of <https://functionalley.com/Storage/flashback.html>.
# CAVEAT:       Directory-names used here must be synchronised with 'formatForBackup.bash'.

.PHONY: backup scrub zero

DIR_BACKUP	= Documents
DIR_MASTER	= ~/$(DIR_BACKUP)
DIR_SNAPSHOTS	= .snapshots
FILE_EXCLUSIONS	= exclusions.txt
TIME_FORMAT	= %Y-%m-%dT%H-%M-%S

# Create the missing file.
$(FILE_EXCLUSIONS):
	>$(FILE_EXCLUSIONS);

# Create a missing subvolume.
$(DIR_BACKUP) $(DIR_SNAPSHOTS):
	sudo btrfs subvolume create '$@';

# Create a backup.
backup: $(FILE_EXCLUSIONS) $(DIR_BACKUP) $(DIR_SNAPSHOTS)
	[[ -z $$(find $(DIR_MASTER)/ -xtype l) ]];	# Check for dangling symlinks, which are probably unintended & which rsync can't follow.
	@[[ -z $$(ls '$(DIR_BACKUP)') ]] || sudo btrfs subvolume snapshot -r -- '$(DIR_BACKUP)/' $(DIR_SNAPSHOTS)/$$(date '+$(TIME_FORMAT)');	# Create a readonly snapshot.
	rsync --verbose --archive --update --exclude-from '$(FILE_EXCLUSIONS)' --delete --copy-links -- $(DIR_MASTER)/ './$(DIR_BACKUP)/'	# Sync the backup, following symlinks.

# Checksum the filesystem.
scrub:
	sudo btrfs scrub start -B ./

# Start the next backup from scratch.
zero: $(DIR_BACKUP) $(DIR_SNAPSHOTS)
	@sudo btrfs subvolume list -o -s '$(DIR_SNAPSHOTS)' | sed -e 's/^.* path //' | xargs sudo btrfs subvolume delete;	# Delete any snapshots.
	rm -rf -- $(DIR_BACKUP)/*;	# Delete the backup, leaving the subvolume in place.

