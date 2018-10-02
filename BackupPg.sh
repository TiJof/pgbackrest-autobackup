#!/bin/bash

# Configuration pgbackrest - /etc/pgbackrest.conf
## [global]
## compress=n
##
## repo1-path=/var/lib/pgbackrest
## repo1-retention-full=2
## repo1-retention-diff=6
##
## backup-standby=y
##
## process-max=2
##
## archive-async=y
## spool-path=/var/spool/pgbackrest
## archive-push-queue-max=33M
## compress-level-network=3
##
## [main]
## pg1-port=5432
## pg1-path=/var/lib/postgresql/10/main
## pg1-host=172.25.105.144
## pg2-port=5432
## pg2-path=/var/lib/postgresql/10/main
## pg2-host=172.25.105.193
## pg3-port=5432
## pg3-path=/var/lib/postgresql/10/main
## pg3-host=172.25.105.170

# Restauration depuis le pgbackrest
## sudo -u postgres pgbackrest --stanza=main restore --pg1-path=/var/lib/postgresql/10/main --recovery-option=standby_mode=on --recovery-option=primary_conninfo='host=172.25.105.144 port=5432 user=postgres'


# Binary files
PgBackRest=/usr/bin/pgbackrest
Sudo=/usr/bin/sudo
Date=/bin/date
Grep=/bin/grep
Tr=/usr/bin/tr
Jq=/usr/bin/jq

# Variables
PgUser=postgres
PgBackRestConf=/etc/pgbackrest/pgbackrest.conf
PgBackRestConfDir=/etc/pgbackrest/conf.d/
DirBackup=/var/lib/pgbackrest/backup
LogLevel=info
ExitCode=0
WarnTime="1 day"

for Stanza in $(${Grep} -P '(?!.*global)^\[' ${PgBackRestConf} | ${Tr} -d [] | tr '\n' ' ') $(${Grep} -P '(?!.*global)^\[' ${PgBackRestConfDir}/* | ${Tr} -d [] | tr '\n' ' ') ; do
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
      if [ ${LastBackup} -lt $(${Date} +%s -d "-${WarnTime}") ] ; then echo Backup is too old ; ExitCode=2 ; fi
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
