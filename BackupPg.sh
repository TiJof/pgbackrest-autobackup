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

# Restore standby from pgbackrest
## sudo -u postgres pgbackrest --stanza=main restore --pg1-path=/var/lib/postgresql/10/main --recovery-option=standby_mode=on --recovery-option=primary_conninfo='host=172.25.105.144 port=5432 user=postgres'

# Flag before application update, to restore PITR to a flag
## select pg_create_restore_point ('maj v1.7');
# And to restore
## pgbackrest --stanza=main restore --pg1-path=/var/lib/postgresql/10/restore --type=name --target=main


# Binary files
readonly Date=/bin/date
readonly Grep=/bin/grep
readonly Jq=/usr/bin/jq
readonly PgBackRest=/usr/bin/pgbackrest
readonly Sudo=/usr/bin/sudo
readonly Tr=/usr/bin/tr

# Variables
readonly DirBackup=/var/lib/pgbackrest/backup
readonly LogLevel=info
readonly PgBackRestConf=/etc/pgbackrest/pgbackrest.conf
readonly PgBackRestConfDir=/etc/pgbackrest/conf.d
readonly PgUser=postgres
readonly WarnTime="1 day"

ExitCode=0

# Test if we want only specific stanzas
if [ ! -z ${2+x} ]; then
  # We want ${2} stanzas
  WantedStanzas=$(echo ${2} | tr ',' ' ')
else
  # else we want all of them
  WantedStanzas=$(echo $(${Grep} --no-filename -P '(?!.*global)^\[' ${PgBackRestConf} | ${Tr} -d [] | tr '\n' ' ') $(${Grep} --no-filename -P '(?!.*global)^\[' ${PgBackRestConfDir}/* | ${Tr} -d [] | tr '\n' ' '))
fi

for Stanza in ${WantedStanzas} ; do
  # Let's verify if the stanza is created
  if [ ! -d ${DirBackup}/${Stanza} ] ; then
    # If not the case, create them
    ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} stanza-create --force || (echo Unable to create Stanza ${Stanza} && exit 1)
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
    help)
      echo "
      You can use different things :
      - $0 info : to get the info for each stanzas
      - $0 check : to let pgbackrest check each stanzas
      - $0 monit : to tell your supervision system about the state of your backup
      - $0 (without args) : to launch default backup for today, it will create the stanza automatically if necessary
      - $0 full/incr/diff : to force a backup of specified type
      Default policy for backup is :
      - full on sunday
      - diff on wednesday
      - incr on other days
      "
      exit 0
      ;;
    *)
      Action=${1}
      ;;
  esac

  ${Sudo} -u ${PgUser} ${PgBackRest} --stanza=${Stanza} --log-level-console=${LogLevel} backup --type=${Action} || ExitCode=2

done

exit ${ExitCode}
