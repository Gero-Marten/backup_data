#!/bin/bash


# file: umount.sh
# bk_version 21.09.1

# Copyright (C) 2017 Richard Albrecht
# www.rleofield.de

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------



. ./src_log.sh


FILENAME=$(basename "$0" .sh)

label=$1
#FILENAME="umount:$label"
FILENAME="$label:umount"


if [[ "$label" == *luks ]]
then
	dlog "is luks"
	dlog "LUKS: 'umount /mnt/$label'"
	umount /mnt/$label
	RET=$?
	if test $RET -eq 0
	then
		dlog "LUKS: 'cryptsetup luksClose $label'"
		cryptsetup luksClose $label
		RET=$?
		if test $RET -ne 0
		then
			dlog "LUKS: 'cryptsetup luksClose $label' fails"
			exit 1
		fi
	else
		dlog "LUKS: 'umount /mnt/$label' fails"
		exit 1
	fi
else
	dlog "is not luks, umount normal"
	dlog "'umount /mnt/$label'"
	umount /mnt/$label
	RET=$?
	if test $RET -ne 0
	then
		dlog "'umount /mnt/$label' fails"
		exit 1
	fi
fi


exit 0

# EOF

