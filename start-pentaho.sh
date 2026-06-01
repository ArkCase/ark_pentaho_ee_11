#!/bin/bash
SCRIPT="$(readlink -f "${BASH_SOURCE:-${0}}")"
BASEDIR="$(dirname "${SCRIPT}")"

set -o allexport

. "${BASEDIR}/data/set-pentaho-env.sh"

setPentahoEnv "${BASEDIR}/jre"

set -euo pipefail
. /.functions

### =========================================================== ###
## Set a variable for DI_HOME (to be used as a system property)  ##
## The plugin loading system for kettle needs this set to know   ##
## where to load the plugins from                                ##
### =========================================================== ###
set_or_default BASE_DIR "/app"
set_or_default PENTAHO_HOME "${BASEDIR}/pentaho"
set_or_default DI_HOME "${BASEDIR}/pentaho-solutions/system/kettle"
set_or_default CATALINA_OPTS

###################################################################
# CONFIGURE PERSISTENCE                                           #
###################################################################
set_or_default DATA_DIR "${BASE_DIR}/data"
ensure_dir "${DATA_DIR}"
CATALINA_OPTS+=" -Droot.data.path='${DATA_DIR}'"

set_or_default TEMP_DIR "${DATA_DIR}/temp"
ensure_dir "${TEMP_DIR}"
export CATALINA_TMPDIR="${TEMP_DIR}"

#
# Configure Kettle
#
set_or_default KETTLE_HOME "${DATA_DIR}/pdi"

###################################################################
# CONFIGURE LOGGING                                               #
###################################################################
set_or_default LOGS_DIR "${BASE_DIR}/logs"
ensure_dir "${LOGS_DIR}"
CATALINA_OPTS+=" -Droot.log.path='${LOGS_DIR}'"

#
# Tomcat Logging
#
set_or_default TOMCAT_LOGS_DIR "${LOGS_DIR}/tomcat"
ensure_dir "${TOMCAT_LOGS_DIR}"
CATALINA_OPTS+=" -Dcatalina.log.path='${TOMCAT_LOGS_DIR}'"

set_or_default CATALINA_OUT "${TOMCAT_LOGS_DIR}/catalina.out"
export CATALINA_OUT

###################################################################
# FINAL TOMCAT CONFIGURATIONS                                     #
###################################################################
set_or_default CATALINA_MEM_OPTS "-Xms2048m -Xmx6144m"

CATALINA_OPTS+=" ${CATALINA_MEM_OPTS} -Dsun.rmi.dgc.client.gcInterval=3600000 -Dsun.rmi.dgc.server.gcInterval=3600000 -Dfile.encoding=utf8 -Djava.locale.providers=COMPAT,SPI -DDI_HOME=${DI_HOME@Q} -Dcom.google.protobuf.use_unsafe_pre22_gencode=true"

set_or_default PENTAHO_LICENSE_FILE
set_or_default PENTAHO_LICENSE_HOST
set_or_default PENTAHO_LICENSE_TYPE "NODE_UNLOCKED"

set_or_default PENTAHO_LICENSE_INFORMATION_PATH "/app/pentaho/.pentaho/.license.plt"
export PENTAHO_LICENSE_INFORMATION_PATH

if [ -n "${PENTAHO_LICENSE_FILE}" ] && [ -n "${PENTAHO_LICENSE_HOST}" ] ; then
	require_file_readable "${PENTAHO_LICENSE_FILE}"

	if is_file_readable "${PENTAHO_LICENSE_INFORMATION_PATH}" ; then
		rm -rf "${PENTAHO_LICENSE_INFORMATION_PATH}" &>/dev/null || true
		is_file_readable "${PENTAHO_LICENSE_INFORMATION_PATH}" && warn "Failed to delete the old license info at [${PENTAHO_LICENSE_INFORMATION_PATH}]" || ok "Old license info deleted!"
	else
		ok "No prior license data found at [${PENTAHO_LICENSE_INFORMATION_PATH}]!"
	fi

	CATALINA_OPTS+=" -Dpentaho.license.filetype=${PENTAHO_LICENSE_TYPE@Q} -Dpentaho.license.custom.host.name=${PENTAHO_LICENSE_HOST@Q} -Dpentaho.license.file=${PENTAHO_LICENSE_FILE@Q} -Dpentaho.license.information.path=${PENTAHO_LICENSE_INFORMATION_PATH@Q}"

	ok "License information added:"
	ok "HostID   : [${PENTAHO_LICENSE_HOST}]"
	ok "Checksum : [sha256:$(sha256sum "${PENTAHO_LICENSE_FILE}" | awk '{ print $1 }')]"
	ok "Type     : [${PENTAHO_LICENSE_TYPE}]"
else
	warn "No license information was found"
fi

# The cluster ID will be the pod's hostname
CATALINA_OPTS+=" -Dorg.apache.jackrabbit.core.cluster.node_id=$(hostname)"

# Set the location for the Karaf cache
set_or_default KARAF_DIR "${DATA_DIR}/karaf"
CATALINA_OPTS+=" -Dpentaho.karaf.root.copy.dest.folder=${KARAF_DIR@Q} -Dpentaho.karaf.root.transient=false"

set_as_boolean LOGGING_CONTEXT_ENABLED "true"
set_or_default LOGGING_CONTEXT_SELECTOR "org.apache.logging.log4j.core.async.AsyncLoggerContextSelector"

as_boolean "${LOGGING_CONTEXT_ENABLED}" && \
	[ -n "${LOGGING_CONTEXT_SELECTOR}" ] && \
	CATALINA_OPTS+=" -Dlog4j2.contextSelector=${LOGGING_CONTEXT_SELECTOR}"

set_as_boolean PENTAHO_DEBUG "false"
set_as_boolean PENTAHO_DEBUG_SUSPEND "false"
as_boolean "${PENTAHO_DEBUG_SUSPEND}" && SUSPEND="y" || SUSPEND="n"
as_boolean "${PENTAHO_DEBUG}" && CATALINA_OPTS+=" -Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=${SUSPEND},address=0.0.0.0:8888"

# We're done configuring Tomcat
export CATALINA_OPTS

###################################################################
# FINAL JDK CONFIGURATIONS                                        #
###################################################################
# Add options to Java 11+ to remove illegal reflective access warnings
set_or_default JAVA_OPTS
JAVA_OPTS+=" --add-opens=java.base/sun.net.www.protocol.jar=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.lang=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.io=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.lang.reflect=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.net=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.security=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.util=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.net.www.protocol.file=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.net.www.protocol.ftp=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.net.www.protocol.http=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.net.www.protocol.https=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.reflect.misc=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.management/javax.management=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.management/javax.management.openmbean=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.naming/com.sun.jndi.ldap=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.math=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/sun.nio.ch=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.base/java.nio=ALL-UNNAMED"
JAVA_OPTS+=" --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED"
export JAVA_OPTS

#
# If we want to enable JavaScript for reports, we do the change
#
if as_boolean "${PENTAHO_REPORTS_JAVASCRIPT:-false}" ; then
	warn "Enabling JavaScript within Pentaho reports (beware of PPP-3817 / CVE-2023-3517)"
	OUT="$(sed -ibak -e 's;^\s*#\s*\(.*JavaScriptRule\s*=\s*.*\)$;\1;ig' "${PENTAHO_WEBAPP}/WEB-INF/classes/org/pentaho/platform/engine/services/runtime/plugins.properties" 2>&1)" || fail "Failed to edit the plugin.properties (rc=${?}): ${OUT}"
	ok "Reports JavaScript enabled!"
fi

###################################################################
# LAUNCH PENTAHO                                                  #
###################################################################
export JAVA_HOME="${_PENTAHO_JAVA_HOME}"
set_or_default PENTAHO_SERVER "${PENTAHO_HOME}/pentaho-server"
set_or_default PENTAHO_TOMCAT "${PENTAHO_SERVER}/tomcat"

###################################################################
# CLEAN OUT ANY STALE KARAF STUFF                                 #
###################################################################
clean-karaf

[ ${#} -gt 0 ] || set -- "run"
execute "${PENTAHO_TOMCAT}/bin/catalina.sh" "${@}"
