#!/bin/bash
#
# Generate webserver backup and upload to the cloud 
#
#

# CONFIG VARS
RCLONE_CONFIG=/home/<USERNAME>/.config/rclone/rclone.conf
export RCLONE_CONFIG
RCLONE_NAME="RCLONE CONFIG NAME"
BACKUP_NAME="<BACKUP NAME>"
u=`whoami`

_date=`date +%Y%m%d` 
ROOT_DIR="/backup/$BACKUP_NAME-$_date"

#
# Debug
#
CONFIG_ONLY=1


if [ ! -d "/backup" ]; then
	echo -e "\e[31m [ You must create the directory /backup in root and give $u permissions ]\e[0m"
	exit
fi

LOCKFILE="/var/lock/`basename $0`"
(
  # Wait for lock for 5 seconds
  flock -x -w 15 200 || exit 1

        echo -e "\e[42m [ Mounting /backup directory ]\e[0m"
        /usr/bin/rclone mount --dir-cache-time 96h --cache-tmp-upload-path /tmp/rclone $RCLONE_NAME:/backups /backup --daemon

 ) 200> ${LOCKFILE}

#wait for drive to be mounted
while true
do
        sleep 5

        cnt=`mount | grep $RCLONE_NAME | wc -l`
        if [ $cnt -eq 1 ]
        then
                echo -e "\e[33m [ /backup directory mounted]\e[0m"
                break
        fi
done


if [ ! -d $ROOT_DIR ]; then
	mkdir $ROOT_DIR
else
	SUFFIX=`date +%S`
	ROOT_DIR="/backup/$BACKUP_NAME-$_date-$SUFFIX"
	mkdir $ROOT_DIR
fi

echo -e "\e[33m [ Cleaning /backup directory ]\e[0m"
find /backup -mindepth 1 -maxdepth 1 -type d -ctime +30 | xargs rm -rf


#Skip data backup for config only
if [ $CONFIG_ONLY -eq 0 ]; then

echo -e "\e[32m [ Backing up MySQL databases ]\e[0m"

#
# MySQL Database Backup
#
# Set loginpath local
# requires a backup.cnf with the user and pass (make sure to secure this file)
#
OUTPUTDIR="$ROOT_DIR/mysql"

if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi

rm "$OUTPUTDIR/*gz" > /dev/null 2>&1

databases=`/usr/bin/mysql --defaults-extra-file=/home/<USERNAME>/bin/backup.cnf -e "SHOW DATABASES;" | tr -d "| " | grep -v Database`

for db in $databases; do
    if [[ "$db" != "information_schema" ]] && [[ "$db" != "performance_schema" ]] && [[ "$db" != "mysql" ]] && [[ "$db" != _* ]] ; then
        echo "Dumping database: $db"
        /usr/bin/mysqldump --defaults-extra-file=/home/wheelert/bin/backup.cnf --databases --databases $db > $OUTPUTDIR/`date +%Y%m%d`.$db.sql
        gzip $OUTPUTDIR/`date +%Y%m%d`.$db.sql
    fi
done


#
# WebData
#
echo -e "\e[32m [ Backing up Web data ]\e[0m"
OUTPUTDIR="$ROOT_DIR/websites"
if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi

websites=`ls /www `
for site in $websites; do
	echo "Compressing $site"
	tar -czf $OUTPUTDIR/`date +%Y%m%d`.$site.tar.gz /www/$site > /dev/null 2>&1
done

fi


echo -e "\e[32m [ Backing up Apache Config ]\e[0m"
#
# Apache Config
#
OUTPUTDIR="$ROOT_DIR/apache"
if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi

tar -czf $OUTPUTDIR/`date +%Y%m%d`.apache2.tar.gz /etc/apache2/* > /dev/null 2>&1


echo -e "\e[32m [ Backing up backup scripts ]\e[0m"
#
# Backup the backup scripts
#

OUTPUTDIR="$ROOT_DIR/backup_scripts"
if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi

cp /home/wheelert/bin/* $OUTPUTDIR

echo -e "\e[32m [ Backing up SOCKS proxy Config ]\e[0m"
#
# Proxy configs
#

OUTPUTDIR="$ROOT_DIR/proxy"
if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi

if [ ! /etc/danted.conf ]; then

cp /etc/danted.conf $OUTPUTDIR
tar -czf $OUTPUTDIR/`date +%Y%m%d`.squid.tar.gz /etc/squid/* > /dev/null 2>&1

fi
echo -e "\e[32m [ Backing up Crontabs ]\e[0m"

#
# crontabs
#

OUTPUTDIR="$ROOT_DIR/crontab"
mkdir $OUTPUTDIR
crontab -l > $OUTPUTDIR/'crontab.root'
crontab -l -u <USERNAME> > $OUTPUTDIR/'crontab.<USERNAME>'
tar -czf $OUTPUTDIR/`date +%Y%m%d`.crontabs.tar.gz /etc/crontab/* > /dev/null 2>&1

#
# create python3 module list
#
echo -e "\e[32m [ Backing up Python Module List ]\e[0m"
OUTPUTDIR="$ROOT_DIR/python"
if [ ! -d $OUTPUTDIR ]; then
	mkdir $OUTPUTDIR
fi
pipout=`/usr/bin/pip3 list`
echo "$pipout" > "$OUTPUTDIR/PythonModules.txt"
sleep 5
/usr/bin/python3 -V > "$OUTPUTDIR/PythonVersion.txt"


echo -e "\e[32m [ Unmount /backup directory ]\e[0m"
fusermount -u /backup

echo -e "\e[32m [ Backup Complete ]\e[0m"
