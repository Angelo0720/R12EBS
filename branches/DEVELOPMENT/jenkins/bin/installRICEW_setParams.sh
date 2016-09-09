#!/bin/bash

usage(){
  echo "$0 [ -g <Generate Master Files Only value = true | false> ] [ -p <Protocol value = http | https> ]"
  exit 1
}

while getopts ":g:p:" opt; do
   case "${opt}" in
     g) g=${OPTARG};;
     p) p=${OPTARG};;
   esac
done

if [ -z "${g}" ] || [ -z "${p}" ]
then
  usage
else
  bamboo.GENERATE_MASTER_FILES_ONLY=$g
  bamboo.PROTOCOL=$p
fi
