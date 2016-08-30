#!/bin/bash
##########################################
# Author: Bjorn Erik Hoel, Accenture     #
# Date:   26.Feb.2014                    #
# Name:   xxcu_find_file_version.sh      #
##########################################

. $XXCU_TOP/bin/xxcu_logutil.sh

FILE_NAME="$1"
info "Scanning APPL_TOP"
cd $APPL_TOP

F_EXT=$(echo "$FILE_NAME" | cut -d. -f2)
F_BASE=$(echo "$FILE_NAME" | cut -d. -f1)

if [ "$F_EXT" == "pld" ]; then
  info "Replacing known file type $F_EXT"
  F_EXT="pll"
fi
if [ "$F_EXT" == "java" ]; then
  info "Replacing known file type $F_EXT"
  F_EXT="class"
fi
NEW_FILE=${F_BASE}.${F_EXT}

FILES_TO_GREP=$(find . -name ${NEW_FILE} -print)

for fname in $FILES_TO_GREP; do

  BNAME=$(basename $fname)
  DNAME=$(dirname $fname)

  echo "##########################################################"
  echo "Found: $fname - 'adident Header' output:"
  echo "##########################################################"
  adident Header $fname

done

info "Scanning COMMON_TOP"
cd $COMMON_TOP

FILES_TO_GREP=$(find . -name ${NEW_FILE} -print)

for fname in $FILES_TO_GREP; do

  BNAME=$(basename $fname)
  DNAME=$(dirname $fname)

  echo "##########################################################"
  echo "Found: $fname - 'adident Header' output:"
  echo "##########################################################"
  adident Header $fname

done
