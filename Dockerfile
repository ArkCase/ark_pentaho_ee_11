###########################################################################################################
#
# How to build:
#
# docker build -t arkcase/pentaho-ee:latest .
#
###########################################################################################################

ARG FIPS=""
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG PRIVATE_REGISTRY
ARG VER="11.0.0.3"
ARG BUILD="312"
ARG OS="linux"
ARG ARCH="amd64"
ARG PKG="pentaho"
ARG PENTAHO_VERSION="${VER}-${BUILD}"
ARG JAVA="21"

# AWS args used to pull Pentaho artifacts from S3
ARG AWS_REGION="us-east-1"
ARG S3_BUCKET="armedia-container-artifacts"
ARG S3_PATH="arkcase/pentaho/${PENTAHO_VERSION}/enterprise/"

ARG DISRUPTOR="4.0.0"
ARG DISRUPTOR_SRC="com.lmax:disruptor:${DISRUPTOR}"
ARG MARIADB_DRIVER="3.5.9"
ARG MARIADB_DRIVER_SRC="org.mariadb.jdbc:mariadb-java-client:${MARIADB_DRIVER}"
ARG MYSQL_DRIVER="9.5.0"
ARG MYSQL_DRIVER_SRC="com.mysql:mysql-connector-j:${MYSQL_DRIVER}"
ARG MYSQL_LEGACY_DRIVER="1.0.0"
ARG MYSQL_LEGACY_DRIVER_SRC="com.armedia.mysql:mysql-legacy-driver:${MYSQL_LEGACY_DRIVER}:jar"
ARG POSTGRES_DRIVER="42.7.12"
ARG POSTGRES_DRIVER_SRC="org.postgresql:postgresql:${POSTGRES_DRIVER}"

ARG ARKCASE_MVN_REPO="https://nexus.armedia.com/repository/arkcase"
ARG ARKCASE_PREAUTH_SPRING="6"
ARG ARKCASE_PREAUTH_VERSION="1.5.0"
ARG ARKCASE_PREAUTH_SRC="com.armedia.arkcase.preauth:arkcase-preauth-springsec-v${ARKCASE_PREAUTH_SPRING}:${ARKCASE_PREAUTH_VERSION}:jar"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base-tomcat"
ARG BASE_VER="10"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}${FIPS}:${BASE_VER_PFX}${BASE_VER}"

ARG PENTAHO_SERVER_EE="${PENTAHO_VERSION}"
ARG PAZ_PLUGIN_EE="${PENTAHO_SERVER_EE}"
ARG PDD_PLUGIN_EE="${PENTAHO_SERVER_EE}"
ARG PDI_EE_CLIENT="${PENTAHO_SERVER_EE}"
ARG PIR_PLUGIN_EE="${PENTAHO_SERVER_EE}"

ARG PENTAHO_USER="${PKG}"
ARG PENTAHO_GROUP="${PENTAHO_USER}"
ARG PENTAHO_UID="1998"
ARG PENTAHO_GID="${PENTAHO_UID}"

ARG LB_VER="5.0.1"
ARG LB_SRC="https://github.com/liquibase/liquibase/releases/download/v${LB_VER}/liquibase-${LB_VER}.tar.gz"

FROM amazon/aws-cli:latest AS pentaho-artifacts

ARG AWS_REGION
ARG S3_BUCKET
ARG S3_PATH

RUN --mount=type=secret,id=aws_conf \
    --mount=type=secret,id=aws_auth \
    export AWS_PROFILE="armedia-docker-build" && \
    export AWS_CONFIG_FILE="/run/secrets/aws_conf" && \
    export AWS_SHARED_CREDENTIALS_FILE="/run/secrets/aws_auth" && \
    aws s3 cp --recursive "s3://${S3_BUCKET}/${S3_PATH}" "/artifacts/" --include "*"
COPY "ROOT.war" "/artifacts/"

FROM "${BASE_IMG}"

ARG VER
ARG PKG
ARG ARKCASE_MVN_REPO
ARG ARKCASE_PREAUTH_SRC
ARG PENTAHO_VERSION
ARG JAVA

ARG LB_SRC
ARG LB_VER

ARG DISRUPTOR_SRC
ARG MARIADB_DRIVER_SRC
ARG MYSQL_DRIVER_SRC
ARG MYSQL_LEGACY_DRIVER_SRC
ARG POSTGRES_DRIVER_SRC

ARG PENTAHO_USER
ARG PENTAHO_UID
ARG PENTAHO_GROUP
ARG PENTAHO_GID

ARG PENTAHO_SERVER_EE
ARG PAZ_PLUGIN_EE
ARG PDD_PLUGIN_EE
ARG PDI_EE_CLIENT
ARG PIR_PLUGIN_EE

ENV HOME_DIR="${BASE_DIR}/${PKG}"
ENV LB_DIR="${BASE_DIR}/lb"
ENV PENTAHO_HOME="${HOME_DIR}"
ENV PENTAHO_PDI_HOME="${BASE_DIR}/pentaho-pdi"
ENV PENTAHO_PDI_LIB="${PENTAHO_PDI_HOME}/data-integration/lib"
ENV PENTAHO_PDI="pentaho-pdi"
ENV PENTAHO_PDI_PLUGINS="${PENTAHO_PDI_HOME}/data-integration/plugins"
ENV PENTAHO_SERVER="${PENTAHO_HOME}/pentaho-server"
ENV PENTAHO_TOMCAT="${TOMCAT_HOME}"
ENV PENTAHO_USER="${PENTAHO_USER}"
ENV PENTAHO_VERSION="${PENTAHO_VERSION}"
ENV PENTAHO_WEBAPP="${PENTAHO_TOMCAT}/webapps/pentaho"
ENV DI_HOME="${PENTAHO_SERVER}/pentaho-solutions/system/kettle"

LABEL ORG="Armedia LLC" \
    APP="Pentaho EE" \
    VERSION="${VER}" \
    IMAGE_SOURCE="https://github.com/ArkCase/ark_pentaho_ee" \
    MAINTAINER="Armedia Devops Team <devops@armedia.com>"

#
# Make sure the user's HOME envvar points to the right place
#
ENV HOME="${PENTAHO_HOME}"

ARG CVE_FIX_FLAG="/src/NO-CVE-FIXES"

#
# System setup: Java, cron, the entrypoint, Tomcat's configuration, and the pentaho user
#
RUN --mount=type=bind,target=/src \
    set-java "${JAVA}" && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        cron \
      && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chmod ug+s /usr/sbin/cron && \
    install -o root -g root -m 0755 /src/entrypoint /usr/local/bin && \
    install-to-tomcat /src/server.xml /src/logging.properties /src/catalina.properties conf && \
    ( umask 0027 && mkdir -p "${HOME_DIR}/.postgresql" ) && \
    ln -svf "${CA_TRUSTS_PEM}" "${HOME_DIR}/.postgresql/root.crt" && \
    groupadd --system --gid "${PENTAHO_GID}" "${PENTAHO_GROUP}" && \
    useradd --system --uid "${PENTAHO_UID}" --gid "${PENTAHO_GID}" --groups "${ACM_GROUP},${TOMCAT_GROUP}" --create-home --home-dir "${PENTAHO_HOME}" "${PENTAHO_USER}" && \
    umask 0027 && \
    mkdir -p "${PENTAHO_HOME}/.pentaho" && \
    chown -Rvc "${PENTAHO_USER}:${PENTAHO_GROUP}" "${PENTAHO_HOME}" "${CONF_DIR}" "${DATA_DIR}" "${LOGS_DIR}" "${TEMP_DIR}" && \
    chmod -Rvc u=rwX,g=rX,o= "${CONF_DIR}" "${DATA_DIR}" "${LOGS_DIR}" "${TEMP_DIR}" && \
    chown -vc "${PENTAHO_USER}:${PENTAHO_GROUP}" "${BASE_DIR}" && \
    chmod -vc u=rwx,g=rx,o= "${BASE_DIR}"

#
# The Pentaho installation, from the pinned vendor archives and this version's SQL changesets ONLY. This layer is
# byte-identical from one build to the next (and is thus reused) until those change, as long as everything in it is
# deterministic:
#
#   * nothing here may download "latest" versions, apply CVE fixes, or depend on the date (that goes in the next step)
#   * ownership and modes are only set on what this step creates (touching anything from earlier layers would copy it
#     into this one)
#   * every entry keeps its archive's timestamp (saved right after extraction, and restored at the end), and anything
#     created here gets the archives' newest one, as do the directories from earlier layers that this step modifies
#   * the SQL changesets (adapted from the vendor's create_quartz scripts) take the timestamp of the vendor's
#     create_quartz_postgresql.sql, since their checkout's timestamps vary from one build to the next
#
RUN --mount=type=bind,target=/src \
    --mount=type=bind,from=pentaho-artifacts,target=/s3,id=artifacts,ro=true \
    umask 0027 && \
    MARKER="$(mktemp -p /tmp)" && \
    sleep 1 && \
    export PENTAHO_INSTALL="${PENTAHO_HOME}/install" && \
    mkdir -p "${PENTAHO_INSTALL}" "${PENTAHO_SERVER}" "${PENTAHO_PDI_HOME}" && \
    export SRC_DIR="${PENTAHO_INSTALL}/pentaho-server-manual-ee-${PENTAHO_SERVER_EE}" && \
    unzip "/s3/artifacts/pentaho-server-manual-ee-${PENTAHO_SERVER_EE}.zip" -d "${PENTAHO_INSTALL}" && \
    unzip "${SRC_DIR}/pentaho-solutions.zip" -d "${PENTAHO_SERVER}" && \
    unzip "${SRC_DIR}/pentaho-data.zip" -d "${PENTAHO_SERVER}" && \
    unzip "${SRC_DIR}/jdbc-distribution-utility.zip" -d "${PENTAHO_HOME}" && \
    unzip "${SRC_DIR}/license-installer.zip" -d "${PENTAHO_HOME}" && \
    ln -sv "../../tomcat" "${PENTAHO_SERVER}" && \
    mkdir -p "${TOMCAT_HOME}/webapps/pentaho" "${TOMCAT_HOME}/webapps/pentaho-style" && \
    unzip "${SRC_DIR}/pentaho.war" -d "${TOMCAT_HOME}/webapps/pentaho" && \
    unzip "${SRC_DIR}/pentaho-style.war" -d "${TOMCAT_HOME}/webapps/pentaho-style" && \
    unzip "/s3/artifacts/ROOT.war" -d "${TOMCAT_HOME}/webapps/ROOT" && \
    chmod -R go-w "${TOMCAT_HOME}/webapps/ROOT" && \
    export PENTAHO_SYSTEM="${PENTAHO_SERVER}/pentaho-solutions/system" && \
    unzip "/s3/artifacts/pir-plugin-ee-${PIR_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/s3/artifacts/paz-plugin-ee-${PAZ_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/s3/artifacts/pdd-plugin-ee-${PDD_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/s3/artifacts/pdi-ee-client-${PDI_EE_CLIENT}.zip" -d "${PENTAHO_PDI_HOME}" && \
    unzip "/s3/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/*.sh" -x "pentaho-server/*/*" -d "${PENTAHO_HOME}" && \
    unzip "/s3/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/tomcat/webapps/sw-style/*" -d "${PENTAHO_HOME}" && \
    STAMP="$(find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${TOMCAT_HOME}" -cnewer "${MARKER}" -type f -printf '%T@\n' | sort -n | tail -1 | cut -d. -f1)" && \
    [ -n "${STAMP}" ] && \
    TIMES="$(mktemp -p /tmp)" && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${TOMCAT_HOME}" -cnewer "${MARKER}" -printf '%T@\t%p\n' > "${TIMES}" && \
    find "${PENTAHO_SYSTEM}/default-content" -type f -delete && \
    sed -i 's;docbase=";docBase=";g' "${PENTAHO_TOMCAT}/webapps/pentaho/META-INF/context.xml" && \
    find "${PENTAHO_SERVER}" -type f -iname '*.sh' -exec chmod u=rwx,g=rx,o= '{}' ';' && \
    rm -f "${PENTAHO_SERVER}/promptuser.sh" "${PENTAHO_SERVER}"/*.bat "${PENTAHO_SERVER}"/*.js && \
    rm -fv \
        "${PENTAHO_PDI_LIB}"/mysql-connector-java-*.jar \
        "${PENTAHO_PDI_LIB}"/postgresql-*.jar \
      && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" -type f -name 'hsqldb-*.jar' -delete && \
    unzip "/s3/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/tomcat/lib/*.jar" -d "${PENTAHO_INSTALL}" && \
    ( cd "${PENTAHO_INSTALL}/pentaho-server/tomcat/lib" && cp -vf "pentaho-tomcat-logs.jar" commons-logging-*.jar "${PENTAHO_TOMCAT}/lib" ) && \
    cp "${PENTAHO_SERVER}/pentaho-solutions/native-lib/linux/x86_64"/* "${PENTAHO_TOMCAT}/lib" && \
    xmlstarlet ed -L -P \
        --update '/web-app/context-param[param-name/text() = "solution-path"]/param-value' --value "${PENTAHO_SERVER}/pentaho-solutions" \
        --delete '/web-app/context-param[param-name/text() = "hsqldb-databases"]' \
        --delete '/web-app/listener[contains(listener-class/text(), "HsqldbStartupListener")]' \
        "${PENTAHO_WEBAPP}/WEB-INF/web.xml" \
      && \
    export KETTLE_PLUGINS="${PENTAHO_SYSTEM}/kettle/plugins" && \
    export PDI_PLUGINS="${PENTAHO_PDI_HOME}/data-integration/plugins" && \
    for DIR in "${KETTLE_PLUGINS}" "${PDI_PLUGINS}" ; do \
        [ -f "${CVE_FIX_FLAG}" ] && continue ; \
        rm -rvf \
            "${DIR}/azure-datalake2-vfs" \
            "${DIR}/azure-sqldb" \
            "${DIR}/google-bigquery" \
            "${DIR}/kinesis" \
            "${DIR}/pdi-jms-plugin" \
            "${DIR}/pentaho-ee-streaming-amqp-plugin" \
            "${DIR}/pentaho-streaming-jms-plugin" ; \
    done && \
    find "${BASE_DIR}" -type f -name "mssql-jdbc-*.jar" -delete && \
    find "${BASE_DIR}" -type f -name "ojdbc*.jar" -delete && \
    rm -rvf "${PENTAHO_INSTALL}" && \
    export MANTLE="${PENTAHO_TOMCAT}/webapps/pentaho/mantle" && \
    cp -rf "${MANTLE}/home/properties" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/content" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/css" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/js" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/images" "${MANTLE}/images" && \
    cp -rf "${MANTLE}/browser/lib" "${MANTLE}" && \
    cp -rf "${MANTLE}/browser/css/browser.css" "${MANTLE}/css" && \
    cp -rf "${MANTLE}/browser"/* "${MANTLE}" && \
    [ -d "/src/sql/${PENTAHO_VERSION}" ] && \
    export SQL_TIME_REF="${PENTAHO_SERVER}/data/postgresql/create_quartz_postgresql.sql" && \
    [ -f "${SQL_TIME_REF}" ] && \
    mkdir -p "${LB_DIR}/pentaho" && \
    ( tar --mode=a-x,u=rwX,g=rX,o= --mtime="${SQL_TIME_REF}" -cf - "/src/sql/${PENTAHO_VERSION}" ) | tar --strip-components=3 -C "${LB_DIR}/pentaho" -xvf - && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${LB_DIR}" -cnewer "${MARKER}" ! -type l -perm /o=rwx -exec chmod -c o-rwx '{}' + && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${LB_DIR}" -cnewer "${MARKER}" -exec chown -hc "${PENTAHO_USER}:${PENTAHO_GROUP}" '{}' + && \
    chown -vc root "${PENTAHO_SERVER}" && \
    chmod -vc go-w "${PENTAHO_SERVER}" && \
    find "${TOMCAT_HOME}" -mindepth 2 -cnewer "${MARKER}" -exec chown -hc "${TOMCAT_USER}:${TOMCAT_GROUP}" '{}' + && \
    find "${TOMCAT_HOME}" -mindepth 2 -cnewer "${MARKER}" ! -type l -exec chmod -c u=rwX,g=rX,o= '{}' + && \
    while IFS="$(printf '\t')" read -r T P ; do \
        [ -e "${P}" ] || [ -L "${P}" ] || continue ; \
        touch -h -d "@${T}" "${P}" ; \
    done < "${TIMES}" && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${LB_DIR}" "${TOMCAT_HOME}" -cnewer "${MARKER}" -newermt "@${STAMP}" -exec touch -h -d "@${STAMP}" '{}' + && \
    rm -f "${MARKER}" "${TIMES}" && \
    touch -h -d "@${STAMP}" "${BASE_DIR}" /tmp

#
# Everything that changes more often: the JDBC drivers (hard-linked into PDI and Liquibase), the preauth module,
# Liquibase, the scripts and configuration from this repository, and the CVE fixes. Whatever this step adds or replaces
# gets its final ownership and modes here (and only that, so nothing from the static layer is copied into this one)
#
RUN --mount=type=bind,target=/src \
    --mount=type=secret,id=mvn_get_auth \
    . /run/secrets/mvn_get_auth && \
    umask 0027 && \
    MARKER="$(mktemp -p /tmp)" && \
    sleep 1 && \
    rm -fv \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-java-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
      && \
    mvn-get "${DISRUPTOR_SRC}" "${PENTAHO_TOMCAT}/lib" && \
    mvn-get "${MARIADB_DRIVER_SRC}" "${PENTAHO_TOMCAT}/lib" && \
    mvn-get "${MYSQL_DRIVER_SRC}" "${PENTAHO_TOMCAT}/lib" && \
    mvn-get "${MYSQL_LEGACY_DRIVER_SRC}" "${ARKCASE_MVN_REPO}" "${PENTAHO_TOMCAT}/lib" && \
    mvn-get "${POSTGRES_DRIVER_SRC}" "${PENTAHO_TOMCAT}/lib" && \
    mvn-get "${ARKCASE_PREAUTH_SRC}" "${ARKCASE_MVN_REPO}" "${PENTAHO_TOMCAT}/webapps/pentaho/WEB-INF/lib" && \
    ln -vf \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-legacy-driver-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "${PENTAHO_PDI_LIB}" && \
    mkdir -p "${LB_DIR}" && \
    curl -L --fail "${LB_SRC}" | tar -C "${LB_DIR}" -xzvf - && \
    rm -fv \
        "${LB_DIR}/internal/lib/mariadb-java-client.jar" \
        "${LB_DIR}/internal/lib/postgresql.jar" \
      && \
    ln -vf \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-legacy-driver-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "${LB_DIR}/internal/lib" && \
    find "${LB_DIR}" -cnewer "${MARKER}" ! -type l -exec chmod -c u=rwX,g=rX,o= '{}' + && \
    install -o "${PENTAHO_USER}" -g "${PENTAHO_GROUP}" -m 0755 -t "${PENTAHO_SERVER}/" "/src/start-pentaho.sh" "/src/clean-karaf" && \
    install -o "${PENTAHO_USER}" -g "${PENTAHO_GROUP}" -m 0644 -t "${PENTAHO_SERVER}/pentaho-solutions/system/" "/src/repository.spring.xml" && \
    install -o "${PENTAHO_USER}" -g "${PENTAHO_GROUP}" -m 0644 -t "${LB_DIR}/" "/src/liquibase.properties" && \
    { [ -f "${CVE_FIX_FLAG}" ] || apply-fixes /src/CVE ; } && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" -cnewer "${MARKER}" ! -type l -perm /o=rwx -exec chmod -c o-rwx '{}' + && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" "${LB_DIR}" -cnewer "${MARKER}" -exec chown -hc "${PENTAHO_USER}:${PENTAHO_GROUP}" '{}' + && \
    chown -vc root "${PENTAHO_SERVER}" && \
    chmod -vc go-w "${PENTAHO_SERVER}" && \
    find "${TOMCAT_HOME}" -mindepth 2 -cnewer "${MARKER}" -exec chown -hc "${TOMCAT_USER}:${TOMCAT_GROUP}" '{}' + && \
    find "${TOMCAT_HOME}" -mindepth 2 -cnewer "${MARKER}" ! -type l -exec chmod -c u=rwX,g=rX,o= '{}' + && \
    rm -f "${MARKER}"

USER "${PENTAHO_USER}"

ENV PATH="${PENTAHO_SERVER}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LD_LIBRARY_PATH="${PENTAHO_TOMCAT}/lib"

EXPOSE 8080
WORKDIR "${PENTAHO_HOME}"
