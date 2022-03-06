openbsd-module-ports
====================

A framework to generate OpenBSD ports for things like Ruby Gems and Perl modules

This is a very rough work in progress still.
There are many things it doesn't do yet but for me, it is better than nothing.

TODO
====

* `pkg/DESCR`
* `make makesum`
* `make plist`
* `OpenBSD::PackageModule::Fetch::Gem`
* `OpenBSD::PackageModule::Fetch::PyPy`


WORKFLOW
========

The way I use this currently is to update my perl ports.
This assumes you have a current system with `/usr/ports` checked out and
up to date and have created `/usr/ports/mystuff`.

It assumes you are doing this on a dedicated machine (or possibly in a chroot)
because it expects to be able to pkg_delete all packages to test that things work with only specified dependencies.

* `perl -Ilib bin/get_outdated`
   * You will need to update the script with your portroach `MAINTAINER` address

* `perl -Ilib bin/pkg_module $( perl -Ilib bin/get_outdated | sed -e 's/:.*//' )`
   * This creates updated ports in `/usr/ports/mystuff`
   * I often create `/usr/ports/mystuff-$( date +%Y-%d-%m)` and symlink that to `mystuff`

* `cd /usr/ports/mystuff`

* `openbsd-module-ports/bin/updated_depends | sed -e 's/^/[ ] /' | tee -a TODO`
   * This script looks at all the ports that have been created or updates
   * checks their dependencies and sorts them
   * Ports that depend on others in the list come before them.
   * You can then start at the bottom of the list and work your way up.

* `openbsd-module-ports/bin/remove_unchanged_orig`
   * Removes the `.orig` file for any `PLIST`'s that haven't changed

* Pick a port you want to work on, likely the last in the list, and cd there

* I check `diff pkg/PLIST.orig pkg/PLIST` to see what has changed
   * fixing as appropriate

* Then `diff Makefile.orig Makefile` to see what the automatic updater did wrong
   * fixing as appropriate

* At this point the port should ideally be the way you want to share it.
   * Using tools like `/usr/ports/infrastructure/bin/portcheck`

* `pkg_delete /var/db/pkg/*`
   * to verify that all dependencies are listed.

* I then run `make test` and make sure that all tests run and pass
   * adding `TEST_DEPENDS += ...` if there are skipped tests due to optional modules

* `openbsd-module-ports/bin/test_reverse_both`
   * **THIS SCRIPT WILL RUN `pkg_delete` TO REMOVE ALL PACKAGES**
   * This script builds `sqlports` and queries it to find the reverse dependencies for your port
   * It then runs the test suite for all those reverse dependencies
   * for both the current port in `mystuff` as well as the one in `/usr/ports`
   * writing the results to an `reverse_depends_results` file in each port
   * If you diff these files you can compare the test run results
   * I often grep the diff output for `Result` or `Tests` for a summary

* Look at the files you have and make sure they all look right
   * less $( find . \( -type d -a -name CVS -prune \) -o -type f -print )

* `openbsd-module-ports/bin/mail_port_diff`
   * A slight misnomer as it will actually mail a brand-new port as well
   * sends the mail to `$USER` so expects that you have a working `~/.forward`
   * You can then forward this mail with any additional notes to [`ports@openbsd.org`](mailto:ports@openbsd.org)

* Once the port is approve and committed, you can then remove the directory.
   * and `cvs up` in `/usr/ports`


References
==========

- [Dist::Zilla](https://dzil.org/index.html)
