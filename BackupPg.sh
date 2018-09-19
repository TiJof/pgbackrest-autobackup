#!/bin/bash

# Configuration pgbackrest - /etc/pgbackrest.conf
## [global]
## repo1-path=/var/lib/pgbackrest
## process-max=4
## stop-auto=y
## archive-check=y
## repo1-retention-full=1
## repo1-retention-diff=8
##
## [localhost]
## pg1-path=/var/lib/postgresql/10/main
## pg1-port=5432
##
## [localhost2]
## pg1-path=/var/lib/postgresql/10/test42
## pg1-port=5433

# Binary files
PgBackRest=/usr/bin/pgbackrest
Sudo=/usr/bin/sudo
Date=/bin/date
Grep=/bin/grep
Tr=/usr/bin/tr
Jq=/usr/bin/jq

# Variables
PgUser=postgres
PgBackRestConf=/etc/pgbackrest.conf
DirBackup=/var/lib/pgbackrest/backup
LogLevel=info
ExitCode=0

for Stanza in $(${Grep} -P '(?!.*global)^\[' ${PgBackRestConf} | ${Tr} -d [] | tr '\n' ' ') ; do
  # Let's verify if the stanza is created
  if [ ! -d ${DirBackup}/${Stanza} ] ; then
    # If not the case, create them
    ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} stanza-create || (echo Unable to create Stanza ${Stanza} && exit 1)
  fi

  case "${1}" in
    info)
      # If we request info, don't do backup
      ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} info
      continue
      ;;
    check)
      # If we request check, don't do backup
      ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} check || ExitCode=1
      continue
      ;;
    monit)
      LastBackup=$(${Sudo} -u ${PgUser} ${PgBackRest} --output=json --stanza=${Stanza} info | ${Jq} '.[0] | .backup[-1] | .timestamp.stop')
      echo Last backup was at $(${Date} -d @${LastBackup})
      if [ ${LastBackup} -lt $(${Date} +%s -d '-1 day') ] ; then echo Backup is too old ; ExitCode=2 ; fi
      continue
      ;;
    "")
      ## Full on sunday, diff on wednesday and incr on other days
      ## pgbackrest is kind enough to do a full if we request a diff and no full exist
      ## date +%w return the number of the dayweek, 0 means Sunday
      case "$(${Date} +%w)" in
        0) Action=full;;
        3) Action=diff;;
        *) Action=incr;;
      esac
    ;;
    *)
      Action=${1}
      ;;
  esac

  ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} backup --type=${Action} || ExitCode=2

done

exit ${ExitCode}
