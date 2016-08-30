#!/bin/bash
##########################################
# Author: Bjørn Erik Hoel, Accenture     #
# Date:   28.Mar.2012                    #
# Name:   xxcu_generate_interface.sh     #
##########################################
REPLYTO="DontReply@nowhere.nowhere"

. $XXCU_TOP/bin/xxcu_logutil.sh
# FORCE LOGGING TO STDERR TO MAKE IT VISIBLE IN CONC LOG
export LOG_UTIL_USE_STDERR="Y"

function print_usage
{
	echo "[MAIL_TO=commaseparated,list,of,recipients] $0 <InputFile> <OutputFilePath under $XXIO_TOP/outbound> [RequestID]"
	echo "Example: EMAIL_TO=bjorn-erik.hoel@accenture.com $0 $PROFILES$.OUTFILENAME RICEW_ID_SHORTNAME/INVOICE_DATA_$(date +%Y%m%d_%H%M%S) 123456"	
	echo "RequestID is optional, and used from concurrent manager. - Sending output to that requests logfile"
	echo "NOTE: For multi-file output files, only specify the target directory which all files will be placed in"
}

function check_retval
{
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		echo "CRITICAL ERROR: ABORTING GENERATION"
		echo "Re-generate by having DBA / IT Support issuing the following on Application server:"
		echo "$0 $1 $2"
		exit $RETVAL
	fi
}

#####################################################
if [ $# -lt 2 ]; then
	print_usage
	exit 1
fi

# Determine if this is a multi-file output file
MULTI_FILE=$(head "$1" | grep ^MULTI_FILE_OUTPUT | wc -l)
if [ $MULTI_FILE -eq 0 ]; then

	# Move as atomic operation, this will determine outcome of the print job and also the success of the program
	# Thus controlling rollback or commit
	debug "Setting group write access"
	chmod g+w "$1"
	
	debug "Moving file"
	mv "$1" "$XXIO_TOP/outbound/$2"
	check_retval
	# Copy it back, doesnt matter if this fails or not"
	debug "Copying file back to conc output file"
	cp "$XXIO_TOP/outbound/$2" "$1"
	
	# Archive it, doesnt matter if this fails or not"
	debug "Archiving file"
	cp "$XXIO_TOP/outbound/$2" "$XXIO_TOP/archive/$2"

	ATTACH_COMMAND="-a $XXIO_TOP/outbound/$2"
	echo "Attached file: $(basename $2)" | mutt -s "Interface Files for $(dirname $2)" $ATTACH_COMMAND $MAIL_TO
else
	info "Multiple files being generated"
	FILES_TO_CREATE=$(cat "$1" | grep -v ^MULTI_FILE_OUTPUT | cut -d: -f2 | sort -u)
	info "Found the following files to be created:	
$FILES_TO_CREATE"
	info "Processing...."
	TEMP_DIRNAME="/tmp/xxcu_generate_file_$(basename $1)"
	debug "Creating directory: $TEMP_DIRNAME"
	mkdir -p "$TEMP_DIRNAME"
	check_retval
	
	if [ ! -d $TEMP_DIRNAME ]; then
		error "No directory: $TEMP_DIRNAME"
		exit 1
	fi

	# Process the input file line by line, and split it into according new files
	cat "$1" | grep -v ^MULTI_FILE_OUTPUT | while read file_line 
	do
		FILENAME=$(echo $file_line | cut -d: -f2)
		check_retval
		TEXT="$(echo "${file_line}" | cut -d: -f4- )"
		check_retval
		touch "$TEMP_DIRNAME/$FILENAME"
		check_retval
		if [ ! -f "$TEMP_DIRNAME/$FILENAME" ]; then
			error "Unable to write to file: $TEMP_DIRNAME/$FILENAME"
			exit 1		
		fi
		debug "FILENAME: $FILENAME"
		debug "TEXT: $TEXT"
		echo "$TEXT" >> "$TEMP_DIRNAME/$FILENAME"
		check_retval
		
	done
	
	if [ "$MAIL_TO" != "" ]; then
		info "Emailing $MAIL_TO"
		ATTACH_COMMAND=$(echo "$FILES_TO_CREATE" | xargs -Irepl echo "-a $TEMP_DIRNAME/repl")
		ATTACH_COMMAND=$(echo $ATTACH_COMMAND)
		debug "$ATTACH_COMMAND"

		echo "The following files were created:
$FILES_TO_CREATE
" | mutt -s "Interface Files for $2" $ATTACH_COMMAND $MAIL_TO
	fi
	info "All files have been successfully written to temporary directory... Moving them all to final destination"
	
	FILE_COUNT=$(find "$TEMP_DIRNAME" -type f | wc -l)
	if [ $FILE_COUNT -eq 0 ]; then
		info "Nothing to do"
		info "Removing temporary directory $TEMP_DIRNAME"
		rmdir "$TEMP_DIRNAME"
		exit 0
	fi
	FILES_TO_MOVE=$(find "$TEMP_DIRNAME" -type f)
	info "Archiving files"
	for file in $FILES_TO_MOVE; do
		#debug "cp '$TEMP_DIRNAME/$file' '$XXIO_TOP/archive/$2/'"
		#cp "$TEMP_DIRNAME/$file" "$XXIO_TOP/archive/$2/"	
		debug "cp '$file' '$XXIO_TOP/archive/$2/'"
		cp "$file" "$XXIO_TOP/archive/$2/"	
	done
	debug "Setting group write access"
	chmod g+w $TEMP_DIRNAME/*
	
	info "Issuing: 	mv $TEMP_DIRNAME/* $XXIO_TOP/outbound/$2"
  	mv "$TEMP_DIRNAME"/* "$XXIO_TOP/outbound/$2"
	
	if [ $? -ne 0 ]; then
		error "Something went wrong while trying to move the file. Cleaning up files"
		for file in $FILES_TO_MOVE; do
			debug "rm $TEMP_DIRNAME/$file"
			rm $TEMP_DIRNAME/$file
		done
		exit 1
	fi
	info "Removing temporary directory $TEMP_DIRNAME"
	rmdir "$TEMP_DIRNAME"

fi

# List files ready to be picked up
info "Files staged and ready to be picked up in $XXIO_TOP/outbound/$2:"
FILE_LIST="$(ls -al $XXIO_TOP/outbound/$2)"

info "$FILE_LIST"

info "Success"

exit $RETVAL