#!/bin/sh

# Script to change ips on a VestaCP server.
# Usage:
# $0 <oldip> <newip>
#
# Based on crypto's script - https://forum.vestacp.com/viewtopic.php?t=5975
# Modified to suit recent VestaCP versions and Debian/Ubuntu installations
# Tested with vesta 0.9.8 on CentOS 7 and Debian 8
#
# Author Grzegorz C. Olszewski <grzegorz@olszewski.in>

LOG=/var/log/vesta/system.log

MYUID=`/usr/bin/id -u`
if [ "$MYUID" != 0 ]; then
        echo "You require Root Access to run this script";
        exit 0;
fi

if [ $# != 2 ] && [ $# != 3 ]; then
        echo "Usage:";
        echo "$0 <oldip> <newip> [<file>]";
        echo "you gave #$#: $0 $1 $2 $3";
        exit 0;
fi

OLD_IP=$1
NEW_IP=$2

HAVE_HTTPD=1
HAVE_NGINX=1

DATE=`date '+%F %X'`
BIN=`echo $0 | awk -F/ '{print $NF}'`

DISTRO="Centos"
if hash lsb_release 2>/dev/null; then
        DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
fi

if [ $DISTRO = "Debian" ] || [ $DISTRO = "Ubuntu" ]; then
        DEBIANBASED=1
        echo "Running in Debian/Ubuntu mode"
else
        DEBIANBASED=0
        echo "Running in RHEL/CentOS mode"
fi

log()
{
        echo -e "$1";
        echo -e "$1" >> $LOG;
}

swapfile()
{
        if [ ! -e $1 ]; then
                log "Cannot Find $1 to change the IPs. Skipping...";
                return;
        fi

        TEMP="perl -pi -e 's/${OLD_IP}/${NEW_IP}/g' $1"
        eval $TEMP;

        log "$DATE $BIN $1\t: $OLD_IP -> $NEW_IP";
}

if [ $# = 3 ]; then
        swapfile $3;
        exit 0;
fi


IPFILE_OLD=/usr/local/vesta/data/ips/$OLD_IP
IPFILE_NEW=/usr/local/vesta/data/ips/$NEW_IP
if [ ! -e $IPFILE_OLD ]; then
        echo -n "$IPFILE_OLD does not exist.  Do you want to continue anyway? (y/n) : ";
        read YESNO;
        if [ "$YESNO" != "y" ]; then
                exit 0;
        fi
else
        mv -f $IPFILE_OLD $IPFILE_NEW
        log "$DATE $0 $IPFILE_OLD\t: $OLD_IP -> $NEW_IP";
fi

if [ "${HAVE_HTTPD}" -eq 1 ] && [ "${DEBIANBASED}" -eq 0 ]; then
        if [ -e /etc/httpd/conf.d/${OLD_IP}.conf ]; then
                swapfile /etc/httpd/conf.d/${OLD_IP}.conf
                mv -f /etc/httpd/conf.d/$OLD_IP.conf /etc/httpd/conf.d/${NEW_IP}.conf
        fi
        swapfile /etc/httpd/conf.d/mod_extract_forwarded.conf
else
        if [ -e /etc/apache2/conf.d/${OLD_IP}.conf ]; then
                swapfile /etc/apache2/conf.d/${OLD_IP}.conf
                mv -f /etc/apache2/conf.d/$OLD_IP.conf /etc/apache2/conf.d/${NEW_IP}.conf
        fi
fi

if [ "${HAVE_NGINX}" -eq 1 ]; then
        if [ -e /etc/nginx/conf.d/${OLD_IP}.conf ]; then
                swapfile /etc/nginx/conf.d/${OLD_IP}.conf
                mv -f /etc/nginx/conf.d/$OLD_IP.conf /etc/nginx/conf.d/${NEW_IP}.conf
        fi
fi

swapfile /etc/hosts

ULDDU=/usr/local/vesta/data/users

for i in `ls $ULDDU`; do
{
        #replace also config in /home/user/conf/web directory
        find /home/$i/conf/web -type f | xargs sed -i  "s/${OLD_IP}/${NEW_IP}/g"

        if [ ! -d $ULDDU/$i ]; then
                continue;
        fi

        swapfile $ULDDU/$i/web.conf
        swapfile $ULDDU/$i/dns.conf
        for j in `ls $ULDDU/$i/dns/*.conf`; do
        {
                swapfile $j
        };
        done;

        if [ "${HAVE_HTTPD}" -eq 1 ]; then
                swapfile /home/$i/conf/web/httpd.conf
        fi
        if [ "${HAVE_NGINX}" -eq 1 ]; then
                swapfile /home/$i/conf/web/nginx.conf
        fi

        for j in `ls /home/$i/conf/dns/*.db`; do
        {
                swapfile $j
        };
        done;

};
done;

#this is needed to update the serial in the db files.
if [ "${HAVE_HTTPD}" -eq 1 ]; then
    echo "Restarting Apache"
    if [ "${DEBIANBASED}" -eq 1 ]; then
        service apache2 restart
    else
        service httpd restart
    fi
fi
if [ "${HAVE_NGINX}" -eq 1 ]; then
    echo "Restarting nginx"
    service nginx restart
fi

echo "*** Done swapping $OLD_IP to $NEW_IP ***";