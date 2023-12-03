#!/bin/bash

function stopSlapd() {
    systemctl status slapd > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        printf 'INFO: slapd service is running and needs to be stopped.\n'
        printf 'INFO: Stopping slapd service...\n'
        systemctl stop slapd
        if [ $? -ne 0 ]; then
            printf 'ERROR: Failed to stop slapd service.\n'
            exit 1
        fi
        printf 'INFO: Stopped slapd service.'
    fi
}

function cleanSlapd() {
    printf 'INFO: Clearing previous openldap-servers/slapd install.\n'
    systemctl disable slapd
    if [ $? -ne 0 ]; then
        printf 'ERROR: Failed to disable slapd service.\n'
        exit 2
    fi
    rm -rf /etc/openldap/slapd.d
    rm -f /var/lib/ldap/*
    printf 'INFO: Removing openldap-servers.\n'
    dnf -y remove openldap-servers > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        printf 'WARN: Failed to remove openldap-servers.\n'
    fi
    printf 'INFO: Re-installing openldap-servers.\n'
    dnf -y install openldap-servers > /dev/null 2>&1
}

function startSlapd() {
    systemctl start slapd
    if [ $? -ne 0 ]; then
        printf 'ERROR: Failed to start slapd service.\n'
        exit 3
    fi
    printf 'INFO: Started slapd service.\n'
}

dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf -y install openldap-servers openldap-clients openssl
BASEDIR=$(dirname $0)
while true; do
    read -s -p "Password: " SLAPPASS
    printf "\n"
    read -s -p "Confirm Password: " SLAPPASS2
    printf "\n"
    [ "$SLAPPASS" = "$SLAPPASS2" ] && break
    printf 'WARN: Passwords do not match.\n'
done
# SLAPPASS=strongPassword123
stopSlapd
cleanSlapd
sed -i '/CRC.*/d' /etc/openldap/slapd.d/cn=config/olcDatabase={0}config.ldif
sed -i '/olcAccess:.*/c\olcAccess: {0}to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break' /etc/openldap/slapd.d/cn=config/olcDatabase={0}config.ldif
sed -i '/ ,cn=auth.*/d' /etc/openldap/slapd.d/cn=config/olcDatabase={0}config.ldif
startSlapd
SECRET=$(slappasswd -s $SLAPPASS)
sed -i "/olcRootPW:.*/c\olcRootPW: $SECRET" $BASEDIR/schema/chrootpwd.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f $BASEDIR/schema/chrootpwd.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/corba.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/duaconf.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/dyngroup.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/java.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/misc.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/openldap.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/collective.ldif > /dev/null 2>&1
ldapadd -Y EXTERNAL -H ldapi:/// -f $BASEDIR/schema/ppolicy.ldif > /dev/null 2>&1
sed -i "/olcRootPW:.*/c\olcRootPW: $SECRET" $BASEDIR/schema/backend.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f $BASEDIR/schema/backend.ldif > /dev/null 2>&1
stopSlapd
cp /etc/openldap/schema/* $BASEDIR/schema/
if [[ -f "$COBDIR/bin/mfds" ]]; then
    $COBDIR/bin/mfds -l "dc=secldap,dc=com" 2 $BASEDIR/schema/mfds.schema > /dev/null 2>&1
elif [[ ! -f "$BASEDIR/schema/mfds.schema" ]]; then
    printf "mfds and $BASEDIR/schema/mfds.schema not found.\n"
    exit 4
fi
mkdir $BASEDIR/config
rm -rf $BASEDIR/config/*
slaptest -f $BASEDIR/schema/schema_convert.conf -F config
cp config/cn=config/cn=schema/cn={12}container.ldif /etc/openldap/slapd.d/cn=config/cn=schema
cp config/cn=config/cn=schema/cn={13}mfds.ldif /etc/openldap/slapd.d/cn=config/cn=schema
chown -R ldap /etc/openldap/slapd.d
chmod -R 700 /etc/openldap/slapd.d
startSlapd
systemctl enable slapd
mkdir $BASEDIR/log
rm -rf $BASEDIR/log/*
ldapadd -v -D "cn=Manager,dc=secldap,dc=com" -w $SLAPPASS -f $BASEDIR/schema/top.ldif -H ldapi:/// > $BASEDIR/log/top.log
ldapadd -v -D "cn=Manager,dc=secldap,dc=com" -w $SLAPPASS -f $BASEDIR/schema/mf-containers.ldif -H ldapi:/// > $BASEDIR/log/mf-containers.log
if [[ -f "$COBDIR/bin/mfds" ]]; then
    $COBDIR/bin/mfds -e "cn=Micro Focus,dc=secldap,dc=com" "cn=Enterprise Server Users" "cn=Enterprise Server User Groups" "cn=Enterprise Server Resources" 2 "/openldap/schema/mfds-users.ldif" > /dev/null 2>&1
elif [[ ! -f "$BASEDIR/schema/mfds-users.ldif" ]]; then
    printf "mfds and $BASEDIR/schema/mfds-users.ldif not found.\n"
    exit 5
fi
ldapadd -v -D "cn=Manager,dc=secldap,dc=com" -w $SLAPPASS -f $BASEDIR/schema/mfds-users.ldif -H ldapi:/// -c > $BASEDIR/log/mfds-users.log
sed 's/DC=X/CN=Micro Focus,dc=secldap,dc=com/' $COBDIR/etc/es_default_ldap_openldap.ldif > $BASEDIR/schema/es_default_ldap_openldap.ldif
sed -i '/,Data/d' $BASEDIR/schema/es_default_ldap_openldap.ldif
ldapadd -v -D "cn=Manager,dc=secldap,dc=com" -w $SLAPPASS -f $BASEDIR/schema/es_default_ldap_openldap.ldif -H ldapi:/// -c > $BASEDIR/log/es_default_ldap_openldap.ldifes_default_ldap_openldap.ldif
ldapsearch -H ldapi:/// -x -b "cn=subschema" -s base + > $BASEDIR/log/schema.log