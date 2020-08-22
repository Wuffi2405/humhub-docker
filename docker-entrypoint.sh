#!/bin/sh

INTEGRITY_CHECK=${HUMHUB_INTEGRITY_CHECK:-1}
WAIT_FOR_DB=${HUMHUB_WAIT_FOR_DB:-1}
SET_PJAX=${HUMHUB_SET_PJAX:-1}
AUTOINSTALL=${HUMHUB_AUTO_INSTALL:-"false"}

HUMHUB_DB_NAME=${HUMHUB_DB_NAME:-"humhub"}
HUMHUB_DB_HOST=${HUMHUB_DB_HOST:-"db"}
HUMHUB_NAME=${HUMHUB_NAME:-"HumHub"}
HUMHUB_EMAIL=${HUMHUB_EMAIL:-"humhub@example.com"}
HUMHUB_LANG=${HUMHUB_LANG:-"en-US"}
HUMHUB_DEBUG=${HUMHUB_DEBUG:-"false"}

HUMHUB_CACHE_CLASS=${HUMHUB_CACHE_CLASS:-"yii\caching\FileCache"}
HUMHUB_CACHE_EXPIRE_TIME=${HUMHUB_CACHE_EXPIRE_TIME:-3600}

HUMHUB_ANONYMOUS_REGISTRATION=${HUMHUB_ANONYMOUS_REGISTRATION:-1}
HUMHUB_ALLOW_GUEST_ACCESS=${HUMHUB_ALLOW_GUEST_ACCESS:-0}
HUMHUB_NEED_APPROVAL=${HUMHUB_NEED_APPROVAL:-0}

# LDAP Config
HUMHUB_LDAP_ENABLED=${HUMHUB_LDAP_ENABLED:-0}
HUMHUB_LDAP_HOSTNAME=${HUMHUB_LDAP_HOSTNAME}
HUMHUB_LDAP_PORT=${HUMHUB_LDAP_PORT}
HUMHUB_LDAP_ENCRYPTION=${HUMHUB_LDAP_ENCRYPTION}
HUMHUB_LDAP_USERNAME=${HUMHUB_LDAP_USERNAME}
HUMHUB_LDAP_PASSWORD=${HUMHUB_LDAP_PASSWORD}
HUMHUB_LDAP_BASE_DN=${HUMHUB_LDAP_BASE_DN}
HUMHUB_LDAP_LOGIN_FILTER=${HUMHUB_LDAP_LOGIN_FILTER}
HUMHUB_LDAP_USER_FILTER=${HUMHUB_LDAP_USER_FILTER}
HUMHUB_LDAP_USERNAME_ATTRIBUTE=${HUMHUB_LDAP_USERNAME_ATTRIBUTE}
HUMHUB_LDAP_EMAIL_ATTRIBUTE=${HUMHUB_LDAP_EMAIL_ATTRIBUTE}
HUMHUB_LDAP_ID_ATTRIBUTE=${HUMHUB_LDAP_ID_ATTRIBUTE}
HUMHUB_LDAP_REFRESH_USERS=${HUMHUB_LDAP_REFRESH_USERS:-1}

# Mailer Config
HUMHUB_MAILER_SYSTEM_EMAIL_ADDRESS=${HUMHUB_MAILER_SYSTEM_EMAIL_ADDRESS:-"noreply@example.com"}
HUMHUB_MAILER_SYSTEM_EMAIL_NAME=${HUMHUB_MAILER_SYSTEM_EMAIL_NAME:-"HumHub"}
HUMHUB_MAILER_TRANSPORT_TYPE=${HUMHUB_MAILER_TRANSPORT_TYPE:-"php"}
HUMHUB_MAILER_HOSTNAME=${HUMHUB_MAILER_HOSTNAME}
HUMHUB_MAILER_PORT=${HUMHUB_MAILER_PORT}
HUMHUB_MAILER_USERNAME=${HUMHUB_MAILER_USERNAME}
HUMHUB_MAILER_PASSWORD=${HUMHUB_MAILER_PASSWORD}
HUMHUB_MAILER_ENCRYPTION=${HUMHUB_MAILER_ENCRYPTION}
HUMHUB_MAILER_ALLOW_SELF_SIGNED_CERTS=${HUMHUB_MAILER_ALLOW_SELF_SIGNED_CERTS:-0}

export NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE:-10m}
export NGINX_KEEPALIVE_TIMEOUT=${NGINX_KEEPALIVE_TIMEOUT:-65}

wait_for_db() {
	if [ "$WAIT_FOR_DB" == "false" ]; then
		return 0
	fi

	until nc -z -v -w60 $HUMHUB_DB_HOST 3306; do
		echo "Waiting for database connection..."
		# wait for 5 seconds before check again
		sleep 5
	done
}

echo "=="
if [ -f "/var/www/localhost/htdocs/protected/config/dynamic.php" ]; then
	echo "Existing installation found!"

	wait_for_db

	INSTALL_VERSION=$(cat /var/www/localhost/htdocs/protected/config/.version)
	SOURCE_VERSION=$(cat /usr/src/humhub/.version)
	cd /var/www/localhost/htdocs/protected/
	if [[ $INSTALL_VERSION != $SOURCE_VERSION ]]; then
		echo "Updating from version $INSTALL_VERSION to $SOURCE_VERSION"
		php yii migrate/up --includeModuleMigrations=1 --interactive=0
		php yii search/rebuild
		cp -v /usr/src/humhub/.version /var/www/localhost/htdocs/protected/config/.version
	fi
else
	echo "No existing installation found!"
	echo "Installing source files..."
	cp -rv /usr/src/humhub/protected/config/* /var/www/localhost/htdocs/protected/config/
	cp -v /usr/src/humhub/.version /var/www/localhost/htdocs/protected/config/.version

	mkdir -p /var/www/localhost/htdocs/protected/runtime/logs/
	touch /var/www/localhost/htdocs/protected/runtime/logs/app.log

	echo "Setting permissions..."
	chown -R nginx:nginx /var/www/localhost/htdocs/uploads
	chown -R nginx:nginx /var/www/localhost/htdocs/protected/modules
	chown -R nginx:nginx /var/www/localhost/htdocs/protected/config
	chown -R nginx:nginx /var/www/localhost/htdocs/protected/runtime

	wait_for_db

	echo "Creating database..."
	cd /var/www/localhost/htdocs/protected/
	if [ -z "$HUMHUB_DB_USER" ]; then
		AUTOINSTALL="false"
	fi

	if [ "$AUTOINSTALL" != "false" ]; then
		echo "Installing..."
		php yii installer/write-db-config "$HUMHUB_DB_HOST" "$HUMHUB_DB_NAME" "$HUMHUB_DB_USER" "$HUMHUB_DB_PASSWORD"
		php yii installer/install-db
		php yii installer/write-site-config "$HUMHUB_NAME" "$HUMHUB_EMAIL"
		# Set baseUrl if provided
		if [ -n "$HUMHUB_PROTO" ] && [ -n "$HUMHUB_HOST" ]; then
			HUMHUB_BASE_URL="${HUMHUB_PROTO}://${HUMHUB_HOST}${HUMHUB_SUB_DIR}/"
			echo "Setting base url to: $HUMHUB_BASE_URL"
			php yii installer/set-base-url "${HUMHUB_BASE_URL}"
		fi
		php yii installer/create-admin-account

		php yii 'settings/set' 'base' 'cache.class' "${HUMHUB_CACHE_CLASS}"
		php yii 'settings/set' 'base' 'cache.expireTime' "${HUMHUB_CACHE_EXPIRE_TIME}"

		php yii 'settings/set' 'user' 'auth.anonymousRegistration' "${HUMHUB_ANONYMOUS_REGISTRATION}"
		php yii 'settings/set' 'user' 'auth.allowGuestAccess' "${HUMHUB_ALLOW_GUEST_ACCESS}"
		php yii 'settings/set' 'user' 'auth.needApproval' "${HUMHUB_NEED_APPROVAL}"

		if [ "$HUMHUB_LDAP_ENABLED" != "0" ]; then
			echo "Setting LDAP configuration..."
			php yii 'settings/set' 'ldap' 'enabled' "${HUMHUB_LDAP_ENABLED}"
			php yii 'settings/set' 'ldap' 'hostname' "${HUMHUB_LDAP_HOSTNAME}"
			php yii 'settings/set' 'ldap' 'port' "${HUMHUB_LDAP_PORT}"
			php yii 'settings/set' 'ldap' 'encryption' "${HUMHUB_LDAP_ENCRYPTION}"
			php yii 'settings/set' 'ldap' 'username' "${HUMHUB_LDAP_USERNAME}"
			php yii 'settings/set' 'ldap' 'password' "${HUMHUB_LDAP_PASSWORD}"
			php yii 'settings/set' 'ldap' 'baseDn' "${HUMHUB_LDAP_BASE_DN}"
			php yii 'settings/set' 'ldap' 'loginFilter' "${HUMHUB_LDAP_LOGIN_FILTER}"
			php yii 'settings/set' 'ldap' 'userFilter' "${HUMHUB_LDAP_USER_FILTER}"
			php yii 'settings/set' 'ldap' 'usernameAttribute' "${HUMHUB_LDAP_USERNAME_ATTRIBUTE}"
			php yii 'settings/set' 'ldap' 'emailAttribute' "${HUMHUB_LDAP_EMAIL_ATTRIBUTE}"
			php yii 'settings/set' 'ldap' 'idAttribute' "${HUMHUB_LDAP_ID_ATTRIBUTE}"
			php yii 'settings/set' 'ldap' 'refreshUsers' "${HUMHUB_LDAP_REFRESH_USERS}"
		fi

		php yii 'settings/set' 'base' 'mailer.systemEmailAddress' "${HUMHUB_MAILER_SYSTEM_EMAIL_ADDRESS}"
		php yii 'settings/set' 'base' 'mailer.systemEmailName' "${HUMHUB_MAILER_SYSTEM_EMAIL_NAME}"
		if [ "$HUMHUB_MAILER_TRANSPORT_TYPE" != "php" ]; then
			echo "Setting Mailer configuration..."
			php yii 'settings/set' 'base' 'mailer.transportType' "${HUMHUB_MAILER_TRANSPORT_TYPE}"
			php yii 'settings/set' 'base' 'mailer.hostname' "${HUMHUB_MAILER_HOSTNAME}"
			php yii 'settings/set' 'base' 'mailer.port' "${HUMHUB_MAILER_PORT}"
			php yii 'settings/set' 'base' 'mailer.username' "${HUMHUB_MAILER_USERNAME}"
			php yii 'settings/set' 'base' 'mailer.password' "${HUMHUB_MAILER_PASSWORD}"
			php yii 'settings/set' 'base' 'mailer.encryption' "${HUMHUB_MAILER_ENCRYPTION}"
			php yii 'settings/set' 'base' 'mailer.allowSelfSignedCerts' "${HUMHUB_MAILER_ALLOW_SELF_SIGNED_CERTS}"
		fi

		chown -R nginx:nginx /var/www/localhost/htdocs/protected/runtime
		chown nginx:nginx /var/www/localhost/htdocs/protected/config/dynamic.php
	fi
fi

echo "Config preprocessing ..."

if test -e /var/www/localhost/htdocs/protected/config/dynamic.php &&
	grep "'installed' => true" /var/www/localhost/htdocs/protected/config/dynamic.php -q; then
	echo "installation active"

	if [ $SET_PJAX != "false" ]; then
		sed -i \
			-e "s/'enablePjax' => false/'enablePjax' => true/g" \
			-e "s/getenv('HUMHUB_REDIS_HOSTNAME')/'${HUMHUB_REDIS_HOSTNAME}'/g" \
			-e "s/getenv('HUMHUB_REDIS_PORT')/${HUMHUB_REDIS_PORT}/g" \
			-e "s/getenv('HUMHUB_REDIS_PASSWORD')/'${HUMHUB_REDIS_PASSWORD}'/g" \
			-e "s/getenv('HUMHUB_CACHE_CLASS')/'${HUMHUB_CACHE_CLASS}'/g" \
			-e "s/getenv('HUMHUB_QUEUE_CLASS')/'${HUMHUB_QUEUE_CLASS}'/g" \
			-e "s/getenv('HUMHUB_PUSH_URL')/'${HUMHUB_PUSH_URL}'/g" \
			-e "s/getenv('HUMHUB_PUSH_JWT_TOKEN')/'${HUMHUB_PUSH_JWT_TOKEN}'/g" \
			/var/www/localhost/htdocs/protected/config/common.php
	fi

	if [ -n "$HUMHUB_TRUSTED_HOSTS" ]; then
		sed -i \
			-e "s|'trustedHosts' => \['.*'\]|'trustedHosts' => ['$HUMHUB_TRUSTED_HOSTS']|g" \
			/var/www/localhost/htdocs/protected/config/web.php
	fi
else
	echo "no installation config found or not installed"
	INTEGRITY_CHECK="false"
fi

if [ "$HUMHUB_DEBUG" == "false" ]; then
	sed -i '/YII_DEBUG/s/^\/*/\/\//' /var/www/localhost/htdocs/index.php
	sed -i '/YII_ENV/s/^\/*/\/\//' /var/www/localhost/htdocs/index.php
	echo "debug disabled"
else
	sed -i '/YII_DEBUG/s/^\/*//' /var/www/localhost/htdocs/index.php
	sed -i '/YII_ENV/s/^\/*//' /var/www/localhost/htdocs/index.php
	echo "debug enabled"
fi

if [ "$INTEGRITY_CHECK" != "false" ]; then
	echo "validating ..."
	php ./yii integrity/run
	if [ $? -ne 0 ]; then
		echo "validation failed!"
		exit 1
	fi
else
	echo "validation skipped"
fi

echo "Writing Nginx Config"
envsubst "\$NGINX_CLIENT_MAX_BODY_SIZE,\$NGINX_KEEPALIVE_TIMEOUT" < /etc/nginx/nginx.conf > /tmp/nginx.conf
cat /tmp/nginx.conf > /etc/nginx/nginx.conf
rm /tmp/nginx.conf

echo "=="

exec "$@"
