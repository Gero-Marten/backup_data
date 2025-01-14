#!/bin/bash

# file: bk_main.sh
# bk_version 23.12.2


# Copyright (C) 2017-2023 Richard Albrecht
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

# call chain:
# ./bk_main.sh, runs forever, <- this file 
#	./bk_disks.sh,   all disks
#		./bk_loop.sh	all projects in disk
#			./bk_project.sh, one project with 1-n folder trees
#				./bk_rsnapshot.sh,  do rsnapshot
#				./bk_archive.sh,    no history, rsync only


# set -u, which will exit your script if you try to use an uninitialised variable.
#set -u
# set -e exits if subscript fails
#set -e


# prefixes of variables in backup:
# bv_*  - global vars, alle files
# lv_*  - local vars, global in file
# _*    - local in functions or loops
# BK_*  - exitcodes, upper case, BK_



. ./cfg.working_folder
. ./cfg.ssh_login

. ./src_test_vars.sh
. ./src_filenames.sh
. ./src_exitcodes.sh
. ./src_log.sh
. ./src_folders.sh

# values: lv_iscron  = "cron" = backup was started via cronjob
#         lv_iscron != "cron" = backup was started via commandline
readonly lv_iscron=$1

readonly lv_lockfilename="main_lock"

# output goes to 'out_bk_main'
# pwd and current time
echo "working folder: $PWD"
echo "time is:        $( currentdate_for_log )"
# 


readonly lv_tracelogname="main"
readonly lv_cc_logname="main"

tlog "start"



function check_working_folder {
	if [ -d $bv_workingfolder ] && [ $PWD = $bv_workingfolder ]
	then
		dlog ""
	else
		dlog "workingfolder '$bv_workingfolder' is wrong, stop, exit 1 "
		exit 1
	fi

}

readonly lv_call_source=$1
function start_message {
	local _call_source=$lv_call_source
	dlog "========================"
	dlog "===  start of backup ==="
	dlog "===  version 23.12.1 ==="
	dlog "========================"
	local _runningnumber=$( get_runningnumber )

	if [ "$_call_source" = "cron" ]
	then
		dlog "------  is cron start    ------"
		seqlog "Starte Backup mit Cronjob, Nr: $_runningnumber"
	else
		dlog "------  is manual start  ------"
		seqlog "Starte Backup via Terminal, Nr: $_runningnumber"
	fi

	dlog ""
	dlog "--> workingfolder: $bv_workingfolder"
}

function check_if_already_running {
	dlog "pgrep -u $USER   bk_main.sh "
	pidcount=$(  pgrep -u $USER   "bk_main.sh" | wc -l )

	# pid appears twice, because of the subprocess finding the pid
	if [ $pidcount -lt 3 ]
	then
			dlog "backup is not running, start" 
		else
			dlog "backup is running, exit"
			dlog "pid = $pidcount"
			exit 1
	fi

}



function check_main_lock {
	local _call_source=$lv_call_source

	# remove main_lock, if is startet via cron_start_backup.sh
	dlog "check '$lv_lockfilename', if exists"
	if [ $_call_source = "cron" ]
	then
		dlog "check '$lv_lockfilename' for 'cron_start_backup'"
		if [ -f $lv_lockfilename ]
		then
			dlog " '$lv_lockfilename' exists, remove and continue"
			dlog "remove $lv_lockfilename"
			rm $lv_lockfilename
        		dlog "$lv_lockfilename removed"
		fi
	else
		# exit, if main_lock exists and is not startet via cron_start_backup.sh
		dlog "check '$lv_lockfilename' for 'start_backup'"
		if [ -f $lv_lockfilename ]
		then
			echo "backup is running, $lv_lockfilename exists"
			dlog "backup is running, $lv_lockfilename exists, exit 1"
			echo "exit 1"
			dlog "exit 1"
			exit 1
		fi
	fi


	
}

function check_and_remove_rsnapshot_pid_lock {
	if [ -f  rsnapshot.pid ]
	then
		dlog "old rsnapshot.pid found, has backup_data crashed before?"
		rm rsnapshot.pid
	fi
}


# empty '$bv_internalerrors' = internalerrors.txt
# do not clear in main loop
# errors must be present until solved
function clear_internalerrors_list {
	dlog " == "
	dlog " == truncate -s 0 $bv_internalerrors   ==" 
	truncate -s 0 $bv_internalerrors
	dlog " == "
}





function shatestfile(){
	local _file1=$1
	local _lsum1=$2
	local sum=$( sha256sum $_file1 )
	local a=$( echo $sum | cut -f1 -d " " )
#	echo "$a, found sum $a"
	if [ $_lsum1 != $a ]
	then
		dlog "$_file was changed. sha256sum  $a, "
		dlog "         sha256sum  must be $_lsum1 "
		return 1
	fi
	return 0

}

function shatestfiles(){
	local _testfile=$1
	local exitval=0
	local oldifs=$IFS
	while IFS=' ' read -r _lsum _file 
	do
		if [ -f $_file ]
		then
			shatestfile  $_file $_lsum 
			local RET=$?
			if [ $RET -eq 0 ]
			then
				dlog "$_file is ok"
			else
				exitval=1
			fi
		fi
	done < <(cat $_testfile )
	IFS=$oldifs
	return $exitval
}

function shatest(){
	if [ -f "sha256sum.txt" ]
	then
		dlog " ==  test sha256sums"
		#RETSHA256=$( sha256sum -c --quiet sha256sum.txt.sh )
		shatestfiles sha256sum.txt
		RETSHA256=$?
		if [ ${RETSHA256} -gt 0  ]
		then
			dlog "sha256sum check fails, create new 'sha256sum.txt' by call of 'get_sha256.sh'"
			dlog "and start with './start_backup.sh' again"
			exit 0
		else
			dlog "sha256sum check ok"
		fi
	else
		dlog "sha256sum check fails, create new 'sha256sum.txt.sh' by call of 'get_sha256.sh'"
		dlog "and start with './start_backup.sh' again"

	fi
}

function list_test_flags(){
	dlog " ==  list test flags and variables =="
	dlog "maxfillbackupdiskpercent (70):    	$bv_maxfillbackupdiskpercent"
	dlog "no_check_disk_done (0):			$bv_test_no_check_disk_done"
	dlog "check_looptimes (1):              	$bv_test_check_looptimes"
	dlog "execute_once (0):                 	$bv_test_execute_once"
	dlog "do_once_count (0):                	$bv_test_do_once_count"
	dlog "test_use_minute_loop (0):              	$bv_test_use_minute_loop"
	dlog "test_short_minute_loop (0):            	$bv_test_short_minute_loop"
	dlog "test_short_minute_loop_seconds_10 (0): 	$bv_test_short_minute_loop_seconds_10"
	dlog "test_minute_loop_duration (2):         	$bv_test_minute_loop_duration"
	dlog "daily_rotate (1):                 	$bv_daily_rotate"
	dlog " == "
}


# check folder for rsnapshot configuration files
function check_configuration_folders(){
	local _folderlist="$bv_conffolder $bv_intervaldonefolder $bv_retainscountfolder $bv_backup_messages_testfolder $bv_donefolder $bv_excludefolder $bv_oldlogsfolder $bv_preconditionsfolder $bv_retainscountfolder"
	for _folder in $_folderlist
	do
		dlog "check folder: '$_folder'"
		if  [ ! -d $_folder   ]
		then
			dlog "folder: '$_folder' doesn't exist, exit 1"
			dlog "===================="
			exit 1
		fi
	done
}


function check_ssh_configuration(){
	dlog "ssh configuration: $sshlogin, $sshhost, $sshport, $sshtargetfolder"
	if [  -z  "${sshtargetfolder}" ]
	then
		dlog "ssh configuration: 'sshtargetfolder' is empty"
		return 1
	fi
	return 0
}
function check_ssh_configuration2(){
	dlog "ssh configuration 2: $sshlogin2, $sshhost2, $sshport2, $sshtargetfolder2"
	if [  -z  "${sshtargetfolder2}" ]
	then
		dlog "ssh configuration 2: 'sshtargetfolder2' is empty"
		return 1
	fi
	return 0
}


function rotate_logs(){
	# date in year month day
	local _date=$(date +%Y-%m-%d)
	local _oldlogdir=$bv_oldlogsfolder/$_date

	# if _oldlogdir with date doesn't exist
	if [ ! -d "$_oldlogdir" ]
	then

		if [ $bv_daily_rotate -eq 1 ]
		then
			dlog "rotate log to '$_oldlogdir'"
			mkdir $_oldlogdir
			mv aa_* $_oldlogdir
			mv rr_* $_oldlogdir
			mv $bv_logfile $_oldlogdir
			mv $bv_errorlog $_oldlogdir
			mv $bv_tracefile $_oldlogdir
			if [ -f label_not_found.log ]
			then
				mv label_not_found.log "$_oldlogdir"
			fi
			# and create new and empty files
			touch $bv_logfile
			touch $bv_errorlog
			touch $bv_tracefile
			dlog "log rotated to '$_oldlogdir'"

			# date: year month 01
			local _date01=$(date +%Y-%m-01)
			# if _date = first of month, save logs 
			if [[ ${_date01} == ${_date} ]]
			then
				dlog "rotate monthly at '$_date'"
				mv successloglines.txt $_oldlogdir
				touch successloglines.txt 
			fi
		fi
	fi
}

function set_lock(){
	local _runningnumber=$( printf "%05d"  $( get_loopcounter ) )
	local _lock_date=`date +%Y%m%d-%H%M%S`
	echo "${_lock_date}: create file '$lv_lockfilename'"
	touch $lv_lockfilename
	echo "$_runningnumber" > $lv_lockfilename

}

function release_lock(){
	if [ -f $lv_lockfilename ]
	then
		local _release_date=`date +%Y%m%d-%H%M%S`
		echo "$_release_date: remove file '$lv_lockfilename'"
		rm $lv_lockfilename
	fi
}


check_working_folder
start_message $lv_iscron
check_if_already_running
check_main_lock $lv_iscron
check_and_remove_rsnapshot_pid_lock
clear_internalerrors_list 

# if fails, create sha file, if needed
# sha256sum *.sh > sha256sum.txt.sh
shatest


dlog ""
list_test_flags

# check folder for rsnapshot configuration files
check_configuration_folders

# check ssh values in cfg.ssh_login
if [  -n  "${sshlogin}" ]
then
	if ! check_ssh_configuration
	then
		dlog "ssh login value is emtpy"
	fi
fi

if [  -n  "${sshlogin2}" ]
then
	if  ! check_ssh_configuration2
	then
		dlog "ssh login value 2 is emtpy"
	fi
fi

# loop, until 'bk_disks.sh' returns  not '$BK_NORMALDISKLOOPEND'

do_once_counter=0

seqlog ""

seqlog "==========================="

while true
do
	dlog "" 
	_runningnumber=$( get_runningnumber )
	# is incremented after 'bk_disks.sh' in 'increment_loop_counter'
	

	seqlog "neuer Durchgang, Nr: $_runningnumber"
	tlog "counter $_runningnumber"
	dlog " ===== start main loop ($_runningnumber) =====" 
	dlog " ===   version 23.10.1   ==="

        # only in t40
        # in t40 only
        _hostname="$(hostname)"
	dlog "hostname: $_hostname"


	# rotate log
	rotate_logs

	dlog ""
	# set lock
	set_lock


	main_start="$bv_conffolder/main_begin.sh"
               #  e.g. conf/sdisk_start,sh

	dlog "check for '$main_start' shell script"
	# in conf folder
	# shell script, executed at start of disk


	if test -f "$main_start"
	then
		dlog "execute: '$main_start'"
		eval ./$main_start
	else
		dlog "'$main_start' not found, no special function is executed at start of main loop"
	fi


	# call 'bk_disks.sh' to loop over all backup disks 
	##########################################################################################
	./bk_disks.sh $lv_iscron
	RET=$?
	# RET can't be 'readonly'
	##########################################################################################

	# exit values from 'bk_disks.sh'
	# exit $BK_EXECONCESTOPPED - test 'exec once' stopped
	# exit $BK_NORMALDISKLOOPEND  - 99, normal end
	# exit $BK_STOPPED -   normal stop, file 'stop' detected


	main_end="$bv_conffolder/main_end.sh"
	dlog "check for '$main_end' shell script"
	# in conf folder
	# shell script, executed at end of main

	if test -f "$main_end"
	then
		dlog "execute: '$main_end', "

		eval ./$main_end
	else
		dlog "'$main_end' not found, no special function is executed at end of main loop"
	fi


	# release lock
	release_lock

	

	# increment counter 
	increment_loop_counter
	_runningnumber=$( get_runningnumber )


#       RET = EXECONCESTOPPED,    if stop ist executed by 'test_execute_once' = 1
#       RET = NORMALDISKLOOPEND,  if all is ok and normal loop
#       RET = STOPPED,            if stop ist executed by hand and 'test_execute_once' = 0

	endmsg=""
	if [ $RET -eq $BK_NORMALDISKLOOPEND ]
	then
		endmsg="all is ok, normal loop"
	fi
	if [ $RET -eq $BK_STOPPED ]
	then
		endmsg="stop ist executed manually"
	fi
	if [ $RET -eq $BK_EXECONCESTOPPED ]
	then
		endmsg="stop, is in exec_one loop only"
	fi
	dlog "---  last return says: $endmsg"
	dlog "---    values are: 'normal stop in loop', 'manually stopped', 'run once only'"
	sleep 0.5


	if [ $RET -eq $BK_DLOG_CC_LOGNAME_NOT_SET ]
	then
		echo "dlog cc_logname not set"
		sync
		exit 1

	fi

	#  all was ok, check for next loop
	if [ $RET -eq $BK_NORMALDISKLOOPEND ] 
	then
		if [ -s $bv_internalerrors ]
		then
			dlog "" 
			dlog "errors in backup loop: "
			dlog "" 
			dlog "errors:" 
			dlog "$( cat $bv_internalerrors )"
			dlog "" 
			dlog "$text_marker_error, last loop counter: '$_runningnumber'"
			dlog "" 
		fi
	fi	

	# BK_STOPPED, exit
	if [ $RET -eq $BK_STOPPED ]
	then
		if [ -s $bv_internalerrors ]
		then
			dlog "" 
			dlog "--- stop was set, errors in backup: "
			dlog "" 
			dlog "errors:" 
			dlog "$( cat $bv_internalerrors )" 
			dlog "" 
			dlog "$text_marker_error_in_stop, last loop counter: '$_runningnumber', RET=$RET "
		else
			dlog "$text_marker_stop, end reached, start backup again with './start_backup.sh'"
		fi
		# normal stop via stop.sh
		# no 'test_do_once_count' is set in 'src_test_vars.sh'
		#dlog "stopped with 'stop' file"
		seqlog "Ende des Backup via 'Stop' Kommando: $_runningnumber"
		tlog "end, return from bk_disks: $RET"
		sync
		exit 1
	fi

	if [ $RET -eq $BK_EXECONCESTOPPED ]
	then
		if [ -s $bv_internalerrors ]
		then
			dlog "" 
			dlog "'test_execute_once' was set, errors in backup: "
			dlog "" 
			dlog "errors:" 
			dlog "$( cat $bv_internalerrors )" 
			dlog "" 
			dlog "$text_marker_error, last loop counter: '$_runningnumber', RET=$RET "
		fi


		# check, if _'test_do_once_count' is set
		if [ $bv_test_do_once_count -gt 0 ]
		then
			# increment 'do_once_counter' and check nr of counts
			((do_once_counter=do_once_counter+1))
			dlog "do_once_counter = $do_once_counter"
			if [ $do_once_counter -lt $bv_test_do_once_count ]
			then
				# 'test_do_once_count' is not reached, start new loop
				dlog "$text_marker_test_counter, 'test_do_once_count' loops not reached, '$do_once_counter -lt $bv_test_do_once_count' "
				sleep 5
				# goto end of loop
			else
				# 'test_do_once_count' is reached, exit
				dlog "$text_marker_stop, end, 'test_do_once_count' loops reached, '$do_once_counter -eq $bv_test_do_once_count' "
				seqlog "Ende des Backup, Testlauf mit mehreren Durchgängen: $_runningnumber, Zahl der Durchgänge: $do_once_counter"
				sync
				exit 1
			fi
		else
			# 'test_execute_once' is set, exit
			dlog "$text_marker_stop, end reached, 'test_execute_once', RET: '$RET', exit 1 "
			tlog "end, 'test_execute_once', return from bk_disks.sh: $RET"
			seqlog "Ende des Backup, Testlauf mit einem Durchgang: $_runningnumber"
			sync
			exit 1
		fi
	fi

	# no stop set
	dlog " ----> goto next loop  <----"
	tlog " ----> goto next loop  <----"
	sleep 1

done

# end

dlog "execute loop: shouldn't be reached"
exit 0

# EOF



