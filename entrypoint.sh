#!/bin/bash

### CHECK FOR, AND SET THE DATABASE ###
CNT=0
case "${DB_TYPE}" in
	# WARNING # mysql is still largely untested..
	[Mm][Yy][Ss][Qq][Ll]|[Mm][Yy][Ss][Qq][Ll][Ii]|[Mm][Aa][Rr][Ii][Aa][Dd][Bb]|0)
		srv() {	mysql -u "${DB_USER:-hubzilla}" -p "${DB_PASSWORD:-hubzilla}" -h "${DB_HOST:-mariadb}" -P "${DB_PORT:-3306}" "$@"; }
		db()  { srv -D "${DB_NAME:-hub}" "$@"; }
		sql() { db -e "$@" ; }
		while ! srv -e "status" > /dev/null; do
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

cd /var/www/html

cat <<SMTPCONF > /etc/ssmtp/ssmtp.conf
mailhub=${SMTP_HOST}:${SMTP_PORT}
UseSTARTTLS=${SMTP_USE_STARTTLS}
root=${SMTP_USER}@${SMTP_DOMAIN}
rewriteDomain=${SMTP_DOMAIN}
FromLineOverride=YES
SMTPCONF
if [ "${SMTP_PASS:-'nil'}" != "nil" ]; then
	cat <<SMTPCONF >> /etc/ssmtp/ssmtp.conf
AuthUser=${SMTP_USER}
AuthPass=${SMTP_PASS}
SMTPCONF
fi
echo "root:${SMTP_USER}@${SMTP_DOMAIN}" > /etc/ssmtp/revaliases
echo "www-data:${SMTP_USER}@${SMTP_DOMAIN}" >> /etc/ssmtp/revaliases

# Arrange permissions for folders
for folder in "${folders=addon extend log store view widget}"; do
	echo "Fixing folder: $folder"
	if [ "$folder" = view ]; then
        chmod -R 755 $folder
	else
		chmod 755 $folder
    fi
done

chown www-data:www-data .

### START .HTCONFIG.PHP ###
# If database is detected, .htconfig.php will be created
# otherwise, the user will need to produce their own
if [ ${FORCE_CONFIG:-0} != 0 ]; then
	[ -f .htconfig.php ] && rm '.htconfig.php'
	random_string() {	tr -dc '0-9a-f' </dev/urandom | head -c ${1:-64} ; }
	cat <<BASE > .htconfig.php
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
App::\$config['system']['admin_email'] = '${ADMIN_EMAIL}';
App::\$config['system']['max_import_size'] = 200000;
App::\$config['system']['maximagesize'] = 8000000;
App::\$config['system']['directory_mode']  = DIRECTORY_MODE_NORMAL;
App::\$config['system']['theme'] = 'redbasic';

// LOGROT Plugin Settings
App::\$config['logrot']['logrotpath'] = '${LOGROT_PATH}';
App::\$config['logrot']['logrotsize'] = '${LOGROT_SIZE}';
App::\$config['logrot']['logretained'] = '${LOGROT_MAXFILES}';

// PHP Error Logging Settings
error_reporting(E_ERROR | E_WARNING | E_PARSE );
ini_set('error_log','log/php.out');
//ini_set('log_errors','1');
//ini_set('display_errors', '0');
BASE

case "${VERIFY_EMAIL}" in
	[Yy]|[Yy][Ee][Ss]|[Oo][Nn]|1)
		util/config system verify_email 1
	;;
	*)
		util/config system verify_email 0
	;;
esac

# LOGROT section of .htconfig.php
case "${ENABLE_LOGROT}" in
	[Yy]|[Yy][Ee][Ss]|[Oo][Nn]|1)
		if grep -qE "//App.*logrot" '.htconfig.php'; then
			LINES=$(grep -nE "//App.*logrot" '.htconfig.php' | cut -d : -f 1)
			echo "${LINES[*]}"
			for i in ${LINES[@]}; do
				sed $i's|//App|App|g' .htconfig.php;
			done
		elif grep -qE "App.*logrot" '.htconfig.php'; then
			:
		fi
	;;
	*)
		if grep -qE "//App.*logrot" '.htconfig.php'; then
			:
		elif grep -qE "App.*logrot" '.htconfig.php'; then
			LINES=$(grep -nE "//App.*logrot" '.htconfig.php' | cut -d : -f 1)
			echo "${LINES[*]}"
			for i in ${LINES[@]}; do
				sed $i's|App|//App|g' .htconfig.php;
			done
		fi
	;;
esac

# PHP section of .htconfig.php
case "${DEBUG_PHP}" in
	[Yy]|[Yy][Ee][Ss]|[Oo][Nn]|1)
		if grep -q "//ini_set('log_errors','1')" '.htconfig.php'; then
			sed "s|//ini_set('log_errors','1');|ini_set('log_errors','1');|g" .htconfig.php
			sed "s|//ini_set('display_errors','0');|ini_set('display_errors','0');|g" .htconfig.php
		else
			:
		fi
	;;
	*)
		if grep -q "//ini_set('log_errors','1')" '.htconfig.php'; then
			:
		else
			sed "s|ini_set('log_errors','1');|//ini_set('log_errors','1');|g" .htconfig.php
			sed "s|ini_set('display_errors','0');|//ini_set('display_errors','0');|g" .htconfig.php
		fi
	;;
esac

chown www-data:www-data .htconfig.php
### END .HTCONFIG.PHP ###

	if [ ${REDIS_PATH:-"nil"} != "nil" ]; then
		util/config system session_save_handler redis
		util/config system session_save_path ${REDIS_PATH}
		util/config system session_custom true
	fi

	echo "======== INSTALLING: addons ========"
	for a in ${ADDON_LIST=logrot nsfw superblock diaspora pubcrawl}; do
		util/addons install $a
		case "$a" in
			diaspora)
				util/config system diaspora_allowed 1
			;;
			xmpp)
				util/config xmpp bosh_proxy "https://${DOMAIN}/http-bind"
			;;
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
	util/config system ignore_imagick true
	util/config system register_policy ${REGISTER_POLICY}
	#util/config system disable_email_validation 1
fi

# Extra configurations needed if Hubzilla version is 4 or below
CURVER=$(printf "%d" "${HZ_VERSION}")
MAXVER=$(printf "%d" "5")
if [ CURVER -lt MAXVER ]; then

	echo "======== RUNNING: udall ========"
	util/udall
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

chown -R www-data:www-data /var/www/html/*
chown -R www-data:www-data /var/www/html/.*

echo "Starting $@"
exec "$@"
