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
ARG VER="11.0.0.2"
ARG BUILD="293"
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
ARG MARIADB_DRIVER="3.5.7"
ARG MARIADB_DRIVER_SRC="org.mariadb.jdbc:mariadb-java-client:${MARIADB_DRIVER}"
ARG MYSQL_DRIVER="9.5.0"
ARG MYSQL_DRIVER_SRC="com.mysql:mysql-connector-j:${MYSQL_DRIVER}"
ARG MYSQL_LEGACY_DRIVER="1.0.0"
ARG MYSQL_LEGACY_DRIVER_SRC="com.armedia.mysql:mysql-legacy-driver:${MYSQL_LEGACY_DRIVER}:jar"
ARG POSTGRES_DRIVER="42.7.11"
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

FROM amazon/aws-cli:latest AS src

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

RUN mkdir -p "${HOME_DIR}/.postgresql" && ln -svf "${CA_TRUSTS_PEM}" "${HOME_DIR}/.postgresql/root.crt"

RUN set-java "${JAVA}" && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        cron \
      && \
    apt-get clean && \
    groupadd --system --gid "${PENTAHO_GID}" "${PENTAHO_GROUP}" && \ 
    useradd --system --uid "${PENTAHO_UID}" --gid "${PENTAHO_GID}" --groups "${ACM_GROUP}" --create-home --home-dir "${PENTAHO_HOME}" "${PENTAHO_USER}" && \ 
    mkdir -p "${PENTAHO_HOME}/.pentaho" "${PENTAHO_SERVER}" "${PENTAHO_PDI_HOME}" "${LB_DIR}" && \
    chown -Rvc "${PENTAHO_USER}:${PENTAHO_GROUP}" "${BASE_DIR}" && \
    chmod -Rvc u=rwX,g=rX,o= "${BASE_DIR}" && \
    chmod ug+s /usr/sbin/cron

COPY --chown=root:root --chmod=0755 entrypoint /

USER "${PENTAHO_USER}"

COPY --chown="${PENTAHO_USER}:${PENTAHO_GROUP}" --chmod=0640 "server.xml" "logging.properties" "catalina.properties" "${PENTAHO_TOMCAT}/conf/"

#
# Make sure the user's HOME envvar points to the right place
#
ENV HOME="${PENTAHO_HOME}"

# Install Pentaho Server & Plugins
RUN --mount=type=cache,from=src,target=/src,id=artifacts,ro=true \
    umask 0027 && \
    export PENTAHO_INSTALL="${PENTAHO_HOME}/install" && \
    mkdir -p "${PENTAHO_INSTALL}" && \
    export SRC_DIR="${PENTAHO_INSTALL}/pentaho-server-manual-ee-${PENTAHO_SERVER_EE}" && \
    unzip "/src/artifacts/pentaho-server-manual-ee-${PENTAHO_SERVER_EE}.zip" -d "${PENTAHO_INSTALL}" && \
    unzip "${SRC_DIR}/pentaho-solutions.zip" -d "${PENTAHO_SERVER}" && \
    unzip "${SRC_DIR}/pentaho-data.zip" -d "${PENTAHO_SERVER}" && \
    unzip "${SRC_DIR}/jdbc-distribution-utility.zip" -d "${PENTAHO_HOME}" && \
    unzip "${SRC_DIR}/license-installer.zip" -d "${PENTAHO_HOME}" && \
    ln -sv "../../tomcat" "${PENTAHO_SERVER}" && \
    mkdir -p "${TOMCAT_HOME}/webapps/pentaho" "${TOMCAT_HOME}/webapps/pentaho-style" && \
    unzip "${SRC_DIR}/pentaho.war" -d "${TOMCAT_HOME}/webapps/pentaho" && \
    unzip "${SRC_DIR}/pentaho-style.war" -d "${TOMCAT_HOME}/webapps/pentaho-style" && \
    unzip "/src/artifacts/ROOT.war" -d "${TOMCAT_HOME}/webapps/ROOT" && \
    chmod -R go-w "${TOMCAT_HOME}/webapps/ROOT" && \
    export PENTAHO_SYSTEM="${PENTAHO_SERVER}/pentaho-solutions/system" && \
    unzip "/src/artifacts/pir-plugin-ee-${PIR_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/src/artifacts/paz-plugin-ee-${PAZ_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/src/artifacts/pdd-plugin-ee-${PDD_PLUGIN_EE}.zip" -d "${PENTAHO_SYSTEM}" && \
    unzip "/src/artifacts/pdi-ee-client-${PDI_EE_CLIENT}.zip" -d "${PENTAHO_PDI_HOME}" && \
    unzip "/src/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/*.sh" -x "pentaho-server/*/*" -d "${PENTAHO_HOME}" && \
    unzip "/src/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/tomcat/webapps/sw-style/*" -d "${PENTAHO_HOME}" && \
    find "${PENTAHO_SYSTEM}/default-content" -type f -delete && \
    sed -i 's;docbase=";docBase=";g' "${PENTAHO_TOMCAT}/webapps/pentaho/META-INF/context.xml" && \
    find "${PENTAHO_SERVER}" -type f -iname '*.sh' -exec chmod u=rwx,g=rx,o= '{}' ';' && \
    rm -f "${PENTAHO_SERVER}/promptuser.sh" "${PENTAHO_SERVER}"/*.bat "${PENTAHO_SERVER}"/*.js && \
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
    rm -fv \
        "${PENTAHO_PDI_LIB}"/mysql-connector-java-*.jar \
        "${PENTAHO_PDI_LIB}"/postgresql-*.jar \
      && \
    ln -vf \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-legacy-driver-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "${PENTAHO_PDI_LIB}" && \
    find "${PENTAHO_HOME}" "${PENTAHO_PDI_HOME}" -type f -name 'hsqldb-*.jar' -delete && \
    unzip "/src/artifacts/pentaho-server-ee-${PENTAHO_SERVER_EE}.zip" "pentaho-server/tomcat/lib/*.jar" -d "${PENTAHO_INSTALL}" && \
    ( cd "${PENTAHO_INSTALL}/pentaho-server/tomcat/lib" && cp -vf "pentaho-tomcat-logs.jar" commons-logging-*.jar "${PENTAHO_TOMCAT}/lib" ) && \
    chmod -Rvc o-rwx "${PENTAHO_HOME}" "${PENTAHO_TOMCAT}" "${PENTAHO_PDI_HOME}" && \
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
        rm -rvf \
            "${DIR}/azure-datalake2-vfs" \
            "${DIR}/azure-sqldb" \
            "${DIR}/kinesis" \
            "${DIR}/pdi-jms-plugin" \
            "${DIR}/pentaho-streaming-jms-plugin" ; \
    done && \
    find "${BASE_DIR}" -type f -name "mssql-jdbc-*.jar" -delete && \
    find "${BASE_DIR}" -type f -name "ojdbc*.jar" -delete && \
    rm -rvf "${PENTAHO_INSTALL}"

RUN umask 0027 && \
    curl -L --fail "${LB_SRC}" | tar -C "${LB_DIR}" -xzvf - && \
    cd "${LB_DIR}" && \
    rm -fv \
        internal/lib/mariadb-java-client.jar \
        internal/lib/postgresql.jar \
      && \
    ln -vf \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-legacy-driver-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "internal/lib" && \
    chown -Rvc "${PENTAHO_USER}:${PENTAHO_GROUP}" "${LB_DIR}" && \
    chmod -Rvc u=rwX,g=rX,o= "${LB_DIR}"

# This is grandfathered in ... unsure why this is done
RUN umask 0027 && \
    export MANTLE="${PENTAHO_TOMCAT}/webapps/pentaho/mantle" && \
    cp -rf "${MANTLE}/home/properties" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/content" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/css" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/js" "${MANTLE}" && \
    cp -rf "${MANTLE}/home/images" "${MANTLE}/images" && \
    cp -rf "${MANTLE}/browser/lib" "${MANTLE}" && \
    cp -rf "${MANTLE}/browser/css/browser.css" "${MANTLE}/css" && \
    cp -rf "${MANTLE}/browser"/* "${MANTLE}"

COPY --chown="${PENTAHO_USER}:${PENTAHO_GROUP}" --chmod=0755 "start-pentaho.sh" "clean-karaf" "${PENTAHO_SERVER}/"
COPY --chown="${PENTAHO_USER}:${PENTAHO_GROUP}" --chmod=0644 repository.spring.xml "${PENTAHO_SERVER}/pentaho-solutions/system/"
COPY --chown="${PENTAHO_USER}:${PENTAHO_GROUP}" --chmod=0644 liquibase.properties "${LB_DIR}/"
COPY --chown="${PENTAHO_USER}:${PENTAHO_GROUP}" "sql/${PENTAHO_VERSION}" "${LB_DIR}/pentaho/"

RUN --mount=type=bind,source=CVE,target=/CVE apply-fixes /CVE

# This is for STIG compliance
USER root
RUN chown root "${PENTAHO_SERVER}" && \
    chmod go-w "${PENTAHO_SERVER}"
USER "${PENTAHO_USER}"

ENV PATH="${PENTAHO_SERVER}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LD_LIBRARY_PATH="${PENTAHO_TOMCAT}/lib"

EXPOSE 8080
WORKDIR "${PENTAHO_HOME}"
ENTRYPOINT [ "/entrypoint" ]
