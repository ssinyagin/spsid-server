#  Copyright (C) 2013  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

#

SUBDIRS = . lib share

EXTRA_DIST = \
	etc/spsid_siteconfig.pl


siteconf_s = etc/spsid_siteconfig.pl
siteconf_d = @siteconfdir@
siteconf_df = $(siteconf_d)/spsid_siteconfig.pl

install-data-local:
	$(mkinstalldirs) $(DESTDIR)$(plugconfdir)
	if test ! -e $(siteconf_df); then \
	  $(mkinstalldirs) $(DESTDIR)$(siteconf_d); \
	  $(INSTALL_DATA) $(siteconf_s) $(DESTDIR)$(siteconf_df); fi

dist-hook:
	date >DIST_REVISION
	git branch -vv >>DIST_REVISION
	cp DIST_REVISION $(distdir)/


test: all
	if test x$(clientlibdir) = x; then \
	echo "--with-clientlibdir is required for tests" 1>&2; \
	exit 1; fi; \
	if test ! -d $(clientlibdir); then \
	echo "No such directory: $(clientlibdir)" 1>&2; \
	exit 1; fi; \
	if test ! -f $(clientlibdir)/SPSID/Client.pm; then \
	echo "No such file: $(clientlibdir)/SPSID/Client.pm" 1>&2; \
	exit 1; fi; \
	if test x$(clientbindir) = x; then \
	echo "--with-clientbindir is required for tests" 1>&2; \
	exit 1; fi; \
	if test ! -d $(clientbindir); then \
	echo "No such directory: $(clientbindir)" 1>&2; \
	exit 1; fi; \
	if test ! -f $(clientbindir)/spsid_siam_load_yaml; then \
	echo "No such file: $(clientbindir)/spsid_siam_load_yaml" 1>&2; \
	exit 1; fi; \
	SPSID_SRV_TOP=@abs_top_builddir@ SPSID_CL_BIN=$(clientbindir) \
	SPSID_CL_LIB=$(clientlibdir) PERL=$(PERL) $(SHELL) t/run_tests.sh
