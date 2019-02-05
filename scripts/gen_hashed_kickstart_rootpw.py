#!/usr/bin/env python3
# -*- coding: UTF-8 -*-
'''
    Hashed paswword generator for kickstart files.
    Copyright (C) 2018-* MAIBACH ALAIN

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    Contact: alain.maibach@gmail.com / 13100 Aix-La Duranne - FRANCE.
'''

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4

__author__ = "Alain Maibach"
__status__ = "Beta tests"


import sys
import crypt
import getpass

if len(sys.argv) > 1:
    USER_PASSWORD = sys.argv[1]

    print(crypt.crypt(USER_PASSWORD, crypt.mksalt(crypt.METHOD_MD5)))
    print(crypt.crypt(USER_PASSWORD, crypt.mksalt(crypt.METHOD_SHA256)))
    print(crypt.crypt(USER_PASSWORD, crypt.mksalt(crypt.METHOD_SHA512)))
else:
    USER_PASSWORD = getpass.getpass()

    print("\n# md5")
    print("rootpw --iscrypted {}".format(crypt.crypt(USER_PASSWORD,
                                                     crypt.mksalt(crypt.METHOD_MD5)
                                                     )))
    print("# sha256")
    print("rootpw --iscrypted {}".format(crypt.crypt(USER_PASSWORD,
                                                     crypt.mksalt(crypt.METHOD_SHA256)
                                                     )))
    print("# sha512")
    print("rootpw --iscrypted {}".format(crypt.crypt(USER_PASSWORD,
                                                     crypt.mksalt(crypt.METHOD_SHA512)
                                                     )))
