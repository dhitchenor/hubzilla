# Hubzilla Docker image
[Hubzilla](https://framagit.org/hubzilla/core) as a [docker image](https://hub.docker.com/r/dhitchenor/hubzilla) (based on php:8.2-fpm-alpine) in a multi-arch (amd64, armv6/7, arm64) format.

# Features
- Automatic setup
- Integral addons, preinstalled
- env file for easy configuration/toggling of features

## Supported environment variables:
| Variable            | Description                                                                                                                          |
|---------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| DB_TYPE             | Database type: postgres or mysql                                                                                                     |
| DB_HOST             | Host name of the database                                                                                                            |
| DB_PORT             | Database port number, set to empty to use the default of your DB_TYPE (aka 3306 for mysql)                                           |
| DB_NAME             | Database name                                                                                                                        |
| DB_USER             | Database user                                                                                                                        |
| DB_PASSWORD         | Database user password                                                                                                               |
| SMTP_HOST           | Mail server hostname                                                                                                                 |
| SMTP_PORT           | Mail server port number                                                                                                              |
| SMTP_USER           | User name for the mail server                                                                                                        |
| SMTP_DOMAIN         | Mail domain                                                                                                                          |
| SMTP_PASS           | Password for the user on the mail server, if set empty, then no authentication on the smtp server will be used                       |
| DOMAIN              | Web domain  name for hubzilla                                                                                                        |
| ADMIN_EMAIL         | Administrators email of the deployed hub                                                                                             |
| REDIS_PATH          | If set (to something like " tcp://redis") then php sessions will be stored in this redis server  (useful for horizontal scalability) |
| LDAP_SERVER         | LDAP server name (dont forget to add "ldapauth" to the ADDON_LIST)                                                                   |
| LDAP_ROOT_DN        | LDAP username to connect to (ex: cn=admin,dc=domain,dc=com)                                                                          |
| LDAP_ADMIN_PASSWORD | Password for that LDAP user                                                                                                          |
| LDAP_BASE           | Path to look for users in the directory (ex: ou=people,,dc=domain,dc=com)                                                            |
| ADDON_LIST          | Addons to activate during initial configuration                                                                                      |

# Quick Setup
1. Clone git repository to your server (or wherever you desire Hubzilla to be deployed from).
    - eg: git clone https://github.com/dhitchenor/hubzilla
    - NOTE: you will need to install git for this to work, otherwise you can download the repository in a zip file from GitHub

2. Edit nginx.conf:
    - on line 19, change 'domain.com' to your desired server name (eg. funnylookingfaces.com)
    - on line 43, change 'hub:9000' to match the name (not, container name) of your hubzilla container in your docker-compose.yml file
        - NOTE: retain the port (:9000) on this line

3. Edit .env file
    - depending on the database that you are using, uncomment/comment the appropriate lines, ENSURE the code for the unused database is commented out
        - HINT: don't change any port numbers, unless you have to; including database ports, nginx ports, hubzilla ports
    - change the DOMAIN value to reflect the domain name that you changed earlier, in the nginx.conf file
    - change the DB agnostic options to reflect your desired database credentials
        - HINT: if you already have a database, you will need to change the values of DB_NAME, DB_USER, and DB_PASSWORD to reflect that database; if no database is present, a database is created for you using these details
        - HINT: DB_HOST should match the name (not, container name) of the database container used for hubzilla or within the docker-compose.yml file

4. Edit docker-compose.yml file
    - depending on the database that you are using, uncomment/comment the appropriate healthcheck lines, ENSURE the code for the unused database is commented out
    - change all code in between the '< >' symbols, to reflect the appropriate local directories (4 in total)
        - NOTE: do not keep the '< >' symbols; remove them
        - ENSURE: both '<DESIRED_WEB_ROOT_LOCATION>' lines (for the hubzilla, and nginx containers) need to be the same location

5. Ensure placement of files
    - if you have changed the location of any files that you gained when cloning this git repository, ensure the changes are reflected within the docker-compose.yml file 
        - by default, the '.env' file should be in the same directory as the docker-compose file
        - by default, the nginx.conf file is in the config folder

6. Run docker compose. eg, docker-compose up -d (or docker-compose up, if you want to see the output of the deployment), and navigate to your domain (in a web browser), after deployment has finished.