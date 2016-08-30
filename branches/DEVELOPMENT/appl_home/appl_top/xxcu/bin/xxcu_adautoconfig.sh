#!/bin/bash
# Author: Bjorn Erik Hoel, Accenture
# Purpose: Wrapper for adautocfg.sh that takes backup of critical files
. $XXCU_TOP/bin/xxcu_logutil.sh

CONTEXT_DIR=$(dirname ${CONTEXT_FILE})
ARCHIVE_DIR="${CONTEXT_DIR}/archive.$(date +'%Y%m%d_%H%M%S')"

info "Important files will be archived in: $ARCHIVE_DIR"
mkdir -p $ARCHIVE_DIR

info 'Archiving $TNS_ADMIN/tnsnames.ora'
cp $TNS_ADMIN/tnsnames.ora $ARCHIVE_DIR/
info 'Archiving $TNS_ADMIN/listener.ora'
cp $TNS_ADMIN/listener.ora $ARCHIVE_DIR/
info 'Archiving $CONTEXT_FILE'
cp $CONTEXT_FILE $ARCHIVE_DIR/

cd $ADMIN_SCRIPTS_HOME
info "Running adautocfg.sh"
./adautocfg.sh
