Baremetal cloud (aka the alternator)
====================================

Goal
----
Make managing baremetals as easy as virtual machines.

Proof-of-concept
----------------
```
onhost/setup/rescue-env # assumes apt and ensures dependencies

. onhost/disklayout/two-disk-raid0 # check the dsl, you should get along just fine
baremetal_config # the complete state is in env, verify it. If you get an error, redo disklayout using /bin/bash

. onhost/install/ubuntu-focal # this will wipe disks, backups are your friend

reboot # it should just work!
```

Backlog
-------
long!
