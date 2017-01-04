#! /bin/bash

# Ameir Abdeldayem
# http://www.ameir.net
# You are free to modify and distribute this code,
# so long as you keep my name and URL in it.

#----------------------Start of Script------------------#

function die () {
  echo >&2 "$@"
  exit 1
}

CONFIG=${1:-`dirname $0`/backupmongodb.conf}
[ -f "$CONFIG" ] && . "$CONFIG" || die "Could not load configuration file ${CONFIG}!"

# check of the backup directory exists
# if not, create it
if  [ ! -d $BACKDIR ]; then
  echo -n "Creating $BACKDIR..."
  mkdir -p $BACKDIR
  echo "done!"
fi

for KEY in "${!DBHOST[@]}"; do
  echo "Backing up MongoDB database on ${DBHOST[$KEY]}..."

  DBS=${DBNAMES[$KEY]}
  COLLECTIONS=''

  # filter out the collections to backup
  if [ -n "${DBCOLLECTIONSEXCLUDE[$KEY]}" ]; then
    for collection in ${DBCOLLECTIONSEXCLUDE[$KEY]}; do
      COLLECTIONS="$COLLECTIONS --excludeCollection=$collection "
    done
  fi

  for database in $DBS; do
    echo -n "Backing up database $database..."
    test ${DBHOST[$KEY]} = "localhost" && SERVER=`hostname -f` || SERVER=${DBHOST[$KEY]}
    mongodump --host=${DBHOST[$KEY]} --port=${DBPORT[$KEY]} --username=${DBUSER[$KEY]} --password=${DBPASS[$KEY]} \
      ${DBOPTIONS[$KEY]} --db=$database $COLLECTIONS --out=$BACKDIR/$SERVER-$database-$DATE-mongodbbackup
    cd $BACKDIR
    $COMPRESSION_COMMAND $SERVER-$database-$DATE-mongodbbackup.$COMPRESSION_EXTENSION $SERVER-$database-$DATE-mongodbbackup
    echo "done!"
  done
done

# if you have the mail program 'mutt' installed on
# your server, this script will have mutt attach the backup
# and send it to the email addresses in $EMAILS

if  [ $MAIL = "y" ]; then
  BODY="Your backup is ready! Find more useful scripts and info at http://www.ameir.net. \n\n"
  BODY=$BODY`cd $BACKDIR; for file in *$DATE-mongodbbackup.$COMPRESSION_EXTENSION; do md5sum ${file};  done`
  ATTACH=`for file in $BACKDIR/*$DATE-mongodbbackup.$COMPRESSION_EXTENSION; do echo -n "-a ${file} ";  done`

  echo -e "$BODY" | mutt -s "$SUBJECT" $ATTACH -- $EMAILS
  if [[ $? -ne 0 ]]; then
    echo -e "ERROR:  Your backup could not be emailed to you! \n";
  else
    echo -e "Your backup has been emailed to you! \n"
  fi
fi

if  [ $DELETE = "y" ]; then
  OLDDBS=`cd $BACKDIR; find . -name "*-mongodbbackup.$COMPRESSION_EXTENSION" -mtime +$DAYS`
  REMOVE=`for file in $OLDDBS; do echo -n -e "delete ${file}\n"; done` # will be used in FTP

  cd $BACKDIR; for file in $OLDDBS; do rm -v ${file}; done
  if  [ $DAYS = "1" ]; then
    echo "Yesterday's backup has been deleted."
  else
    echo "The backups from $DAYS days ago and earlier have been deleted."
  fi
fi

if  [ $DUPLICITY = "y" ]; then
  duplicity full --progress $DUPLICITY_OPTIONS $BACKDIR $DUPLICITY_TARGET_URL
fi

if  [ $S3_UPLOAD = "y" ]; then
  aws $AWS_CLI_OPTIONS s3 sync $BACKDIR s3://$S3_PATH $S3_OPTIONS
fi

if  [ $FTP = "y" ]; then
  echo "Initiating FTP connection..."

  cd $BACKDIR
  ATTACH=`for file in *$DATE-mongodbbackup.$COMPRESSION_EXTENSION; do echo -n -e "put ${file}\n"; done`

  for KEY in "${!FTPHOST[@]}"; do
    echo -e "\nConnecting to ${FTPHOST[$KEY]} with user ${FTPUSER[$KEY]}..."
    ftp -nvp <<EOF
    open ${FTPHOST[$KEY]} ${FTPPORT[$KEY]}
    user ${FTPUSER[$KEY]} ${FTPPASS[$KEY]}
    tick
    mkdir ${FTPDIR[$KEY]}
    cd ${FTPDIR[$KEY]}
    $REMOVE
    $ATTACH
    quit
EOF
  done

  echo -e  "FTP transfer complete! \n"
fi

echo "Your backup is complete!"
