#!/bin/bash

# Error trapping from https://gist.github.com/oldratlee/902ad9a398affca37bfcfab64612e7d1
__error_trapper() {
  local parent_lineno="$1"
  local code="$2"
  local commands="$3"
  echo "error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}
trap '__error_trapper "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"' ERR

set -euE -o pipefail
shopt -s failglob

cd /data
rm -f lojban-list.maildir.zip
echo "Getting maildir zip"
wget --no-verbose https://mail.lojban.org/lists-plain/lojban-list/lojban-list.maildir.zip
echo "Unzipping"
unzip -o -u lojban-list.maildir.zip
echo "Refresh of maildir complete"
