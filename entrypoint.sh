#!/bin/bash

CURVER=${VER_FULL}
[ -f /var/www/html/version ] && CURVER=$(cat /var/www/html/version|sed 's/\..*//')
if ! [ -f /var/www/html/version ] || ! diff /hubzilla/version /var/www/html/version; then
	cp -Rapf /hubzilla/* /hubzilla/.htaccess /var/www/html/
	FORCE_CONFIG=1
fi
# Not sure what this actually does
#if [ "${1:-"failed"}" != "crond" ]; then

### CHECK FOR, AND SET THE DATABASE ###
CNT=0
case "${DB_TYPE}" in		## WARNING ## mysql is still largely untested..
	[Mm][Yy][Ss][Qq][Ll]|[Mm][Yy][Ss][Qq][Ll][Ii]|[Mm][Aa][Rr][Ii][Aa][Dd][Bb]|0)
		srv() {	mysql -u "${DB_USER=hubzilla}" -p "${DB_PASSWORD=hubzilla}" -h "${DB_HOST=mariadb}" -P "${DB_PORT:=3306}" "$@"; }
		db()  { srv -D "${DB_NAME=hub}" "$@"; }
		sql() { db -e "$@" ; }
		while ! srv -e "status" >/dev/null; do
			echo "Waiting for MariaDB/MySQL to be ready ($((CNT+=1)))"
			sleep 2
		done
		if ! sql 'SELECT count(*) FROM pconfig;' >/dev/null; then
			echo "======== INSTALLING: database schema ========"
			db < install/schema_mysql.sql
			if [ $? -ne 0 ]; then
				echo "======== ERROR: Installing schema generated errors ========"
				echo "======== RESULT: Continuing.. See repo if further errors occur ========"
			fi
			FORCE_CONFIG=1
		fi
		DB_TYPE=0
	;;
	[Pp][Ss][Qq][Ll]|[Pp][Gg][Ss][Qq][Ll]|[Pp][Oo][Ss][Tt][Gg][Rr][Ee][Ss]|1)
		db() { PGPASSWORD="${DB_PASSWORD=hubzilla}" psql -h "${DB_HOST=postgres}" -p "${DB_PORT=5432}" -U "${DB_USER=hubzilla}" -d "${DB_NAME=hub}" -wt "$@"; }
		sql() {	db -c "$@"; }
		while ! sql '\q'; do
			echo "Waiting for Postgres to be ready ($((CNT+=1)))"
			sleep 2
		done
		if ! sql 'SELECT count(*) FROM pconfig;' >/dev/null; then
			echo "======== INSTALLING: database schema ========"
			db < install/schema_postgres.sql
			if [ $? -ne 0 ]; then
				echo "======== ERROR: Installing schema generated errors ========"
				echo "======== RESULT: Continuing.. See repo if further errors occur ========"
			fi
			FORCE_CONFIG=1
		fi
		DB_TYPE=1
	;;
	*)
		echo "======== ERROR: Unknown DB_TYPE=${DB_TYPE=Unknown} ========"
		echo "======== RESULT: Skipping DB Setup/Check ========"
		FORCE_CONFIG=0
	;;
esac


cat > /etc/ssmtp/ssmtp.conf <<END
mailhub=${SMTP_HOST}:${SMTP_PORT}
UseSTARTTLS=${SMTP_USE_STARTTLS}
root=${SMTP_USER}@${SMTP_DOMAIN}
rewriteDomain=${SMTP_DOMAIN}
FromLineOverride=YES
END
if [ ${SMTP_PASS=nil} != "nil" ]; then
	cat >> /etc/ssmtp/ssmtp.conf <<END
AuthUser=${SMTP_USER}
AuthPass=${SMTP_PASS}
END
fi
echo "root:${SMTP_USER}@${SMTP_DOMAIN}">/etc/ssmtp/revaliases
echo "www-data:${SMTP_USER}@${SMTP_DOMAIN}">>/etc/ssmtp/revaliases

# Arrange permissions for folders
folders=("store" "addon" "extend" "view" "widget")
for folder in "${folders[@]}"; do
	echo "Fixing folder: $folder"
	chown -R www-data:www-data $folder
	if [ ${folder} = "view" ]; then
        chmod -R 755 $folder
	else
		chmod 755 $folder
    fi
done

chown www-data:www-data .

### START .HTCONFIG.PHP ###

# If database is detected, .htconfig.php while be created
# otherwise, the user will need to produce their own
if [ ${FORCE_CONFIG=0} != 0 ]; then
	[ -f .htconfig.php ] && rm '.htconfig.php'
	random_string() {	tr -dc '0-9a-f' </dev/urandom | head -c ${1:-64} ; }
	cat > .htconfig.php <<ENDBASE
<?php
\$db_host = '${DB_HOST}';
\$db_port = '${DB_PORT}';
\$db_user = '${DB_USER}';
\$db_pass = '${DB_PASSWORD}';
\$db_data = '${DB_NAME}';
\$db_type = '${DB_TYPE}';

// The following configuration maybe configured later in the Admin interface
// They can also be set by 'util/pconfig'
App::\$config['system']['timezone'] = '${TIMEZONE}';
App::\$config['system']['baseurl'] = 'https://${DOMAIN}';
App::\$config['system']['sitename'] = '${SITE_NAME}';
App::\$config['system']['location_hash'] = '$(random_string)';
App::\$config['system']['transport_security_header'] = 1;
App::\$config['system']['content_security_policy'] = 1;
App::\$config['system']['register_policy'] = REGISTER_OPEN;
App::\$config['system']['register_text'] = '';
App::\$config['system']['admin_email'] = '${ADMIN_EMAIL}';
App::\$config['system']['max_import_size'] = 200000;
App::\$config['system']['maximagesize'] = 8000000;
App::\$config['system']['directory_mode']  = DIRECTORY_MODE_NORMAL;
App::\$config['system']['theme'] = 'redbasic';

// PHP Error Logging Settings
error_reporting(E_ERROR | E_WARNING | E_PARSE );
ini_set('error_log','log/php.out');
ENDBASE
# PHP section of .htconfig.php
	case "${DEBUG_PHP}" in
		[Yy]|[Yy][Ee][Ss]|[Oo][Nn]|1)
			if grep -q "//ini_set('log_errors','1')" '.htconfig.php'; then
				sed "s|//ini_set('log_errors','1');|ini_set('log_errors','1');|g" .htconfig.php
				sed "s|//ini_set('display_errors','0');|ini_set('display_errors','0');|g" .htconfig.php
			elif grep -q "ini_set('log_errors','1')" '.htconfig.php'; then
				:
			else
				cat >> .htconfig.php <<ENDPHPLOG
ini_set('log_errors','1');
ini_set('display_errors', '0');
ENDPHPLOG
			fi
		;;
		*)
			if grep -q "//ini_set('log_errors','1')" '.htconfig.php'; then
				:
			elif grep -q "ini_set('log_errors','1')" '.htconfig.php'; then
				sed "s|ini_set('log_errors','1');|//ini_set('log_errors','1');|g" .htconfig.php
				sed "s|ini_set('display_errors','0');|//ini_set('display_errors','0');|g" .htconfig.php
			else
				cat >> .htconfig.php <<ENDPHPLOG
//ini_set('log_errors','1');
//ini_set('display_errors','0');
ENDPHPLOG
			fi
		;;
	esac
# LOGROT section of .htconfig.php
	if ! grep -qE "LOGROT Plugin Settings" '.htconfig.php'; then
		cat >> .htconfig.php <<ENDBASE2

// LOGROT Plugin Settings
ENDBASE2
	fi
	case "${ENABLE_LOGROT}" in
		[Yy]|[Yy][Ee][Ss]|[Oo][Nn]|1)
			if grep -qE "//App.*logrot" '.htconfig.php'; then
				LINES=($(grep -nE "//App.*logrot" '.htconfig.php' | cut -d : -f 1))
				echo "${LINES[*]}"
				for i in ${LINES[@]}; do
					sed $i's|//App|App|g' .htconfig.php; 
				done
			elif grep -qE "App.*logrot" '.htconfig.php'; then
				:
			else
				cat >> .htconfig.php <<ENDLOGROT
App::\$config['logrot']['logrotpath'] = '${LOGROT_PATH}';
App::\$config['logrot']['logrotsize'] = '${LOGROT_SIZE}';
App::\$config['logrot']['logretained'] = '${LOGROT_MAXFILES}';
ENDLOGROT
			fi
		;;
		*)
			if grep -qE "//App.*logrot" '.htconfig.php'; then
				:
			elif grep -qE "App.*logrot" '.htconfig.php'; then
				LINES=($(grep -nE "//App.*logrot" '.htconfig.php' | cut -d : -f 1)) 
				echo "${LINES[*]}"
				for i in ${LINES[@]}; do
					sed $i's|App|//App|g' .htconfig.php; 
				done
			else
				cat >> .htconfig.php <<ENDLOGROT
//App::\$config['logrot']['logrotpath'] = '${LOGROT_PATH}';
//App::\$config['logrot']['logrotsize'] = '${LOGROT_SIZE}';
//App::\$config['logrot']['logretained'] = '${LOGROT_MAXFILES}';
ENDLOGROT
			fi
		;;
	esac
### END .HTCONFIG.PHP ###

	if [ ${REDIS_PATH="nil"} != "nil" ]; then
		util/config system session_save_handler redis
		util/config system session_save_path ${REDIS_PATH}
		util/config system session_custom true
	fi

	echo "======== INSTALLING: addons ========"
	for a in ${ADDON_LIST=logrot nsfw superblock diaspora pubcrawl}; do 
		util/addons install $a
		case "$a" in
			diaspora)
				util/config system.diaspora_allowed 1
			;;
			#gnusoc)
			#	util/config system.gnusoc_allowed 1
			#;;
			# jappixmini has not worked for a while now.. 
			#jappixmini)
			#	curl -sL https://framagit.org/hubzilla/addons/raw/cf4c65b4c61804fb586e8ac4b3a3af085bd0396f/jappixmini.tgz > addon/jappixmini.tgz
			#	util/config jappixmini bosh_address "https://$DOMAIN/http-bind";;
			#xmpp)
			#	util/config xmpp bosh_proxy "https://$DOMAIN/http-bind"
			#;;
			ldapauth)
				util/config ldapauth ldap_server ldap://${LDAP_SERVER}
				util/config ldapauth ldap_binddn ${LDAP_ROOT_DN}
				util/config ldapauth ldap_bindpw ${LDAP_ADMIN_PASSWORD}
				util/config ldapauth ldap_searchdn ${LDAP_BASE}
				util/config ldapauth ldap_userattr uid
				util/config ldapauth create_account 1
			;;
		esac
	done
	util/service_class system default_service_class firstclass
	util/config system disable_email_validation 1
	util/config system ignore_imagick true
fi

# Extra configurations needed if Hubzilla version is 4 or below
if [ "${CURVER}" == "4" ]; then

	echo "======== RUNNING: udall ========"
	if [ -d extend ] ; then
		for a in  theme addon widget ; do
			if [ -d extend/$a ]; then
				for b in  `ls extend/$a` ; do
					echo Updating $b
					'util/update_'$a'_repo' $b
				done
			fi
		done
	fi
	echo "======== SUCCESS: udall ========"
	echo "======== RUNNING: z6convert ========"
	echo "This may take a while..."
	php util/z6convert.php
	R=$?
	if [ $R -ne 0 ]; then
		echo "======== FAILED: z6convert ========"
	else
		echo "======== SUCCESS: z6convert ========"
	fi
fi

mkdir -p /var/www/html/xhprof
chown -R www-data:www-data /var/www/html/*
chown -R www-data:www-data /var/www/html/.[^.]*

#fi

echo "Starting $@"
exec "$@"
