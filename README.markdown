# **Flashback**

Implements an encrypted incremental backup strategy on a removable storage-device.

## Prerequisites

**Bash**, **cryptsetup**, **Btrfs**, **GNU make** & **rsync** will be used.

## Documentation

A **Bash**-script is provided to format the device with a **Btrfs**-filesystem on a **LUKS** storage-volume,
documentation for which is included in the product's "**man/man1/**" directory.
A **makefile** is provided to then manage the incremental backup using **rsync**.
See [Flashback](https://functionalley.com/Storage/flashback.html) for a more detailed description.

## License

For information on copying & distributing this package, see the file "**LICENSE**" in the product's installation-directory.

## Bug-reporting

Bug-reports should be emailed to <flashback@functionalley.com>.

It has only been tested on **Linux**.

## Author

This application is written & maintained by Dr. Alistair Ward.

