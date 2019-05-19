#!/bin/bash

# The User Mask (umask) can be managed with the command umask.
# A umask is the reverse value of the octal permission set that files and directories are created with.
# For example, a umask of 0777 creates files with an octal permission value of 0000; no permissions to read, write or execute.
umask 0027

# This will be used to pass any custom paramters to exec at the bottom of this script.
# We will build/fill this env var as we move down the script.
START_PARAMETERS=''

# Check if BITBUCKET_HOME and BITBUCKET_INSTALL variable are found in ENV:
# ------------------------------------------------------------------------
if [ -z "${BITBUCKET_HOME}" ] || [ -z "${BITBUCKET_INSTALL}" ]; then
  echo "One of BITBUCKET_HOME or BITBUCKET_INSTALL variables - or both! - are empty."
  echo "Please ensure that they are set in Dockerfile, or passed as ENV variable."
  echo "Abnormal exit..."
  exit 1
else
  echo "\${BITBUCKET_HOME} is found as: ${BITBUCKET_HOME}"
  echo "\${BITBUCKET_INSTALL} is found as: ${BITBUCKET_INSTALL}"
fi

# Verify TZ_FILE variable in ENV and setup correct timezone for container:
# -----------------------------------------------------------------------
if [ -n "${TZ_FILE}" ]; then
  # There is a time zone file mentioned. Lets see if it actually exists.
  if [ -r ${TZ_FILE} ]; then
    # Set the symbolic link from the timezone file to /home/OS_USERNAME/localtime, which is owned by OS_USERNAME.
    # The link from /home/OS_USERNAME/localtime is already setup as /etc/localtime as user root, in Dockerfile.
    echo "Using ${TZ_FILE} for timezone ..."
    HOME_DIR=$(grep ${OS_USERNAME} /etc/passwd | cut -d ':' -f 6)
    ln -sf ${TZ_FILE} ${HOME_DIR}/localtime
  else
    echo "Specified TZ_FILE ($TZ_FILE) was not found on the file system. Default timezone will be used instead."
    echo "Timezone related files are in /usr/share/zoneinfo/*"
  fi
else
  echo "TZ_FILE was not specified, the defaut TimeZone (${TZ_FILE}) will be used."
fi

# BITBUCKET_HOME should be set in Dockerfile and picked up from environment.
PROPERTIES_FILE="${BITBUCKET_HOME}/shared/bitbucket.properties"


if [ ! -d ${BITBUCKET_HOME}/shared ]; then
  echo "Bitbucket home directory is not populated. Perhaps, this is a blank volume mounted to the pod for the first time!"
  echo "Creating and chown-ing the directory ${BITBUCKET_HOME}/shared ..."
  
  if [ "$DATACENTER_MODE" == "true" ] && [ -n "${BITBUCKET_DATACENTER_SHARE}" ]; then
    echo "Creating link to datacenter volume"
    ln -s ${BITBUCKET_DATACENTER_SHARE} ${BITBUCKET_HOME}/shared
  else
    echo "Creating shared folder"
    mkdir -p ${BITBUCKET_HOME}/shared
  fi

  # If the docker-entrypoint.sh runs as a normal user (set as default in Dockerfile), then the chwown operation will fail.
  # Though it is harmless to fail.
  # It is a safety mechanism, in case someone decides to run the container as root,
  #   in that case, the chown will work and set the correct ownership to the directory tree.
  chown ${OS_USERNAME}:${OS_GROUPNAME} /var/atlassian/application-data -R
fi


# ELASTIC SEARCH:
# --------------
# ES startup can be independently.
# Ideally just disabling the ENV var ELASTICSEARCH_ENABLED should prevent ES from starting.
#   This is what I understood from the Atlassian documentation.
# However, it seems to not work correctly. So below is a little hack.

if [ -z "${ELASTICSEARCH_ENABLED}" ] || [ "${ELASTICSEARCH_ENABLED}" == "false" ] ; then
  echo "Preventing ElasticSearch from starting ..."
  START_PARAMETERS="${START_PARAMETERS} --no-search"
  # The variable START_PARAMETERS is used with the `exec` command at the very bottom of this script.
fi



# Check if DATACENTER_MODE is set to true and BITBUCKET_DATACENTER_SHARE is configured.
# ------------------------------------------------------------------------------
# Some part of this section can be improved using: 
#   https://bitbucket.org/atlassian-docker/docker-atlassian-bitbucket-server/src/base-6/

if [ "$DATACENTER_MODE" == "true" ] && [ -n "${BITBUCKET_DATACENTER_SHARE}" ]; then
  echo "Entering Data Center mode..."
  # Note: Bitbucket Data Center is different from Bitbucket Server.


  # Setting Data Center node name to the hostname of the Pod
  NEW_JVM_ARGS='JVM_SUPPORT_RECOMMENDED_ARGS="-Dcluster.node.name='$(hostname)'"'
  sed -i "/#JVM_SUPPORT_RECOMMENDED_ARGS/c\\$NEW_JVM_ARGS" /opt/atlassian/bitbucket/bin/_start-webapp.sh

  # Remove all entries of hazelcast, before adding new onces  
  sed -i -e '/hazelcast*/d' ${PROPERTIES_FILE}

  SERVER_IP="$(ip addr show eth0 | grep -w inet | cut -d " " -f 6 | cut -d "/" -f 1)"
  echo "Own IP: $SERVER_IP"
  SVC_IP="$(host $BITBUCKET_SERVICE_NAME | grep has | cut -d " " -f 4 | tr "\n" "," | sed -e 's/,$//')"
  echo "Endpoint IPs: $SVC_IP"
  CLUSTER_PEER_IPS="${SVC_IP:-$SERVER_IP}"
  echo "Using cluster IPs: $CLUSTER_PEER_IPS"

  # Adding new entries to bitbucket.properties with hazelcast values
  echo "hazelcast.network.tcpip.members=${CLUSTER_PEER_IPS}" >> ${PROPERTIES_FILE}
  echo "hazelcast.network.tcpip=true" >> ${PROPERTIES_FILE}
  echo "hazelcast.group.name=bitbucket_cluster" >> ${PROPERTIES_FILE}
  echo "hazelcast.group.password=bitbucket_cluster_password" >> ${PROPERTIES_FILE}
else
  echo "Either DATACENTER_MODE is false or BITBUCKET_DATACENTER_SHARE is empty. Refusing to setup Bitbucket Data Center."
  echo "To run Bitbucket Data Center, both need to be set to appropriate values."
fi

# Import SSL Certificates
# ------------------------------------------------------------------------------

echo "\${SSL_CERTS_PATH}: ${SSL_CERTS_PATH}"
echo "\${CERTIFICATE}: ${CERTIFICATE}"
echo "\${ENABLE_CERT_IMPORT}: ${ENABLE_CERT_IMPORT}"

# CERTIFICATE variable existed for importing a single certificate.
# If SSL_CERTS_PATH is empty and CERTIFICATE file is mentioned, extract
#   directory path from CERTIFICATE file as SSL_CERTS_PATH.

if [ -z "${SSL_CERTS_PATH}" ] && [ -n "${CERTIFICATE}" ]; then
  echo "CERTIFICATE found without SSL_CERTS_PATH in ENV variables."
  echo "Extract dirname from CERTIFICATE variable and use it as SSL_CERTS_PATH."
  SSL_CERTS_PATH=$(dirname ${CERTIFICATE})
fi

if [ -z "${JAVA_KEYSTORE_PASSWORD}" ]; then
  echo 'The JAVA_KEYSTORE_PASSWORD is empty. Using the default value.'
  echo 'Use JAVA_KEYSTORE_PASSWORD as an ENV variable.'
  JAVA_KEYSTORE_PASSWORD='changeit'
fi

# If SSL_CERTS_PATH exists, then we can import certificates.
# Whitelisted certificates: *.crt, *.pem
# It does not matter if the directory is empty.
#   In that case, no certificates will be imported.
# The keystore is by default stored in a file named .keystore in the
#   user's home directory.

if [ ${ENABLE_CERT_IMPORT} = true ] && [ ! -z "${SSL_CERTS_PATH}" ]; then
  JAVA_KEYSTORE_FILE=${BITBUCKET_INSTALL}/jre/lib/security/cacerts
  # Loop through all certificates in this directory and import them.
  for CERT in ${SSL_CERTS_PATH}/*.crt ${SSL_CERTS_PATH}/*.pem; do
    echo "Importing certificate: ${CERT} ..."
    ${BITBUCKET_INSTALL}/jre/bin/keytool \
      -noprompt \
      -storepass ${JAVA_KEYSTORE_PASSWORD} \
      -keystore ${JAVA_KEYSTORE_FILE} \
      -import \
      -file ${CERT} \
      -alias $(basename ${CERT})
  done
  echo "Imported certificates:"
  ${BITBUCKET_INSTALL}/jre/bin/keytool \
    -list -keystore ${JAVA_KEYSTORE_FILE} \
    -storepass ${JAVA_KEYSTORE_PASSWORD} \
    -v \
    | egrep "crt|pem"
fi

# Download plugins listed in ${PLUGINS_FILE}
# ------------------------------------------
echo
if [ -r ${PLUGINS_FILE} ]; then
  echo "Found plugins file: ${PLUGINS_FILE} ... Processing ..."
  PLUGIN_IDS_LIST=$(cat ${PLUGINS_FILE} |  sed -e '/\#/d' -e '/^$/d'|  awk '{print $1}')
  if [ -z "${PLUGIN_IDS_LIST}" ] ; then 
    echo "The plugins file - ${PLUGINS_FILE} is empty, skipping plugins download ..."
  else

    for PLUGIN_ID in ${PLUGIN_IDS_LIST}; do 
    echo
      PLUGIN_URL="https://marketplace.atlassian.com/download/plugins/${PLUGIN_ID}"
      echo "Searching Atlassian marketplace for plugin file related to plugin ID: ${PLUGIN_ID} ..."
      PLUGIN_FILE_URL=$(curl -s -I -L  $PLUGIN_URL | grep  -e "location.*http" | cut -d ' ' -f2 | tr -d '\r\n')
      if [ -z "${PLUGIN_FILE_URL}" ]; then
        echo "Could not find a plugin with plugin ID: ${PLUGIN_ID}. Skipping ..."
      else
        PLUGIN_FILENAME=$(basename ${PLUGIN_FILE_URL})
        echo "The plugin file for the plugin ID: ${PLUGIN_ID}, is found to be: ${PLUGIN_FILENAME} ... Downloading ..."
        echo "Saving plugin file as ${BITBUCKET_INSTALL}/app/WEB-INF/atlassian-bundled-plugins/${PLUGIN_FILENAME} ..."
        curl -s $PLUGIN_FILE_URL -o ${BITBUCKET_INSTALL}/app/WEB-INF/atlassian-bundled-plugins/${PLUGIN_FILENAME}
      fi
    done
    echo
  fi

else
  echo "Plugins file not found. Skipping plugin installation."
fi
echo


echo
echo "Finished running entrypoint script(s). Now executing: $@ ${START_PARAMETERS} ..."
echo

# Execute the command specified as CMD in Dockerfile:

exec "$@" ${START_PARAMETERS}

