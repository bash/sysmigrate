#!/bin/sh

PATH="$(cd $(dirname $0) && pwd)"

cp -- "$PATH/sysmigrate.sh" /usr/local/bin/sysmigrate
