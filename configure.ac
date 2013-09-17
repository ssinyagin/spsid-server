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


AC_INIT([spsid],[1.01dev],[ssinyagin@k-open.com])
AC_PREREQ([2.59])
AC_CONFIG_AUX_DIR(conftools)
AC_CANONICAL_HOST
AM_INIT_AUTOMAKE(1.9)

AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(SED, sed, no)
AC_PATH_PROG(RM, rm, no)
AC_PATH_PROG(RMDIR, rmdir, no)
AC_PATH_PROG(FIND, find, no)

AC_PATH_PROG(PLACKUP, plackup, no)

AC_MSG_CHECKING([location of plackup])
if test ${PLACKUP} = no; then
   AC_MSG_ERROR([plackup is not found]);
else
   AC_MSG_RESULT([Ok])
fi


AC_ARG_ENABLE(pkgonly,
        [AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking])])
AC_SUBST(enable_pkgonly)

        
perllibdirs="\'\${perllibdir}\'"

PERLOPTS=
AC_ARG_VAR(PERLINC,  [[] Additional space-separated Perl library paths])
if test ! -z "$PERLINC"; then
   for d in $PERLINC; do
       PERLOPTS="${PERLOPTS} -I${d}"
       perllibdirs=${perllibdirs}"\,\'"${d}"\'"
   done
fi

AC_SUBST(perllibdirs, [${perllibdirs}])


# Check the necessary Perl modules

if test "$enable_pkgonly" != yes; then

   for module in 'JSON' 'DBI' 'Digest::MD5' 'Moose' 'JSON::RPC::Dispatcher' \
      'LWP::UserAgent' 'Try::Tiny' 'YAML' 'TAP::Harness' 'Test::More' \
      'Text::Unidecode' 'Data::UUID'
   do
     AC_MSG_CHECKING([presence of $module])
     if ${PERL} ${PERLOPTS} -e 'use '$module 2>/dev/null; then
         AC_MSG_RESULT([Ok])
     else
         AC_MSG_ERROR([Perl cannot find $module]);
     fi
   done
fi


AC_ARG_VAR(mansec_usercmd, [[1] User commands man section])
if test -z "$mansec_usercmd"; then
   mansec_usercmd='1'; fi

AC_ARG_VAR(mansec_misc, [[7] Miscellaneous man section])
if test -z "$mansec_misc"; then
   mansec_misc='7'; fi

AC_ARG_VAR(perllibdir,  [[LIBDIR/PACKAGE/perl] SPSID Perl libraries])
if test -z "$perllibdir"; then
   perllibdir='${libdir}/${PACKAGE}/perl'; fi

AC_ARG_VAR(pkgdatadir, [[DATADIR/PACKAGE] SPSID data directory])
if test -z "$pkgdatadir"; then
   pkgdatadir='${datadir}/${PACKAGE}'; fi

AC_ARG_VAR(plugconfdir, [[PKGDATADIR/plugconf] Plugin configuration directory])
if test -z "$plugconfdir"; then
   plugconfdir='${pkgdatadir}/plugconf'; fi

AC_ARG_VAR(siteconfdir, [[SYSCONFDIR/spsid] Site configuration files])
if test -z "$siteconfdir"; then
   siteconfdir='${sysconfdir}/spsid'; fi
   
AC_CONFIG_FILES([Makefile bin/Makefile])
AC_CONFIG_FILES([lib/Makefile share/Makefile])
AC_CONFIG_FILES([setup_tools/substvars.sh],[chmod +x setup_tools/substvars.sh])

AC_SUBST(VERSION)

AC_OUTPUT
