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


SUBST = @abs_top_builddir@/setup_tools/substvars.sh

defaultsdir = @pkgdatadir@/conf_defaults

dist_defaults_DATA = \
	conf_defaults/spsid_config.pl


psgidir = @pkgdatadir@/psgi

psgi_DATA = \
	psgi/spsid_jsonrpc.psgi

psgi_SCRIPTS = \
	psgi/spsid_jsonrpc.fcgi

sqldir = @pkgdatadir@/sql

dist_sql_DATA = \
	sql/spsid_schema.ansi.sql


EXTRA_DIST = \
	conf_defaults/spsid_config.pl.in \
	psgi/spsid_jsonrpc.psgi.in \
	psgi/spsid_jsonrpc.fcgi.in


CLEANFILES = $(psgi_DATA) $(psgi_SCRIPTS)



conf_defaults/spsid_config.pl: conf_defaults/spsid_config.pl.in
	$(SUBST) conf_defaults/spsid_config.pl.in > conf_defaults/spsid_config.pl

psgi/spsid_jsonrpc.psgi: psgi/spsid_jsonrpc.psgi.in
	$(SUBST) psgi/spsid_jsonrpc.psgi.in > psgi/spsid_jsonrpc.psgi

psgi/spsid_jsonrpc.fcgi: psgi/spsid_jsonrpc.fcgi.in
	$(SUBST) psgi/spsid_jsonrpc.fcgi.in > psgi/spsid_jsonrpc.fcgi