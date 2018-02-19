FROM multiarch/crossbuild

RUN apt-get update  && \
    apt-get -y --no-install-recommends install apt-file && \
    apt-file update

COPY assets /

ENV OPENSSL openssl-1.1.0g
ENV WIN32 i686-w64-mingw32
ENV WIN64 x86_64-w64-mingw32
ENV OSX32 i386-apple-darwin14
ENV OSX64 x86_64-apple-darwin14
ENV OSXCROSS /usr/osxcross

ENV SDKVERSION MacOSX10.10.sdk
ENV OSXSDK ${OSXCROSS}/SDK/${SDKVERSION}

ENV MAKEOPTS -j 4
ENV OPENSSL_CONFIG no-asm no-hw no-engine no-threads no-dso no-ssl

ENV LANG C.UTF-8

# Java
RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home

# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
RUN ln -svT "/usr/lib/jvm/java-7-openjdk-$(dpkg --print-architecture)" /docker-java-home
ENV JAVA_HOME /docker-java-home

ENV JAVA_VERSION 7u151
ENV JAVA_DEBIAN_VERSION 7u151-2.6.11-2~deb8u1

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION 20140324

RUN set -ex; \
	\
# deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \
		mkdir -p /usr/share/man/man1; \
	fi; \
	\
	apt-get install -y \
		openjdk-7-jdk="$JAVA_DEBIAN_VERSION" \
		ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
	; \
	\
# verify that "docker-java-home" returns what we expect
	[ "$(readlink -f "$JAVA_HOME")" = "$(docker-java-home)" ]; \
	\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'

# see CA_CERTIFICATES_JAVA_VERSION notes above
RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure

# Maven
ARG MAVEN_VERSION=3.5.2
ARG USER_HOME_DIR="/root"
ARG SHA=707b1f6e390a65bde4af4cdaf2a24d45fc19a6ded00fff02e91626e3e42ceaff
ARG BASE_URL=https://apache.osuosl.org/maven/maven-3/${MAVEN_VERSION}/binaries

RUN mkdir -p /usr/share/maven /usr/share/maven/ref \
  && curl -fsSL -o /tmp/apache-maven.tar.gz ${BASE_URL}/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
  && echo "${SHA}  /tmp/apache-maven.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/apache-maven.tar.gz -C /usr/share/maven --strip-components=1 \
  && rm -f /tmp/apache-maven.tar.gz \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_HOME /usr/share/maven
ENV MAVEN_CONFIG "$USER_HOME_DIR/.m2"


# openssl windows
RUN set -x && \
    cd /usr/src && \
    wget https://www.openssl.org/source/${OPENSSL}.tar.gz && \
    tar -xzf ${OPENSSL}.tar.gz && \
    cd ${OPENSSL} && \
    ./Configure ${OPENSSL_CONFIG} --cross-compile-prefix=${WIN32}- --prefix=/usr/${WIN32} --openssldir=/usr/${WIN32} mingw && \
    make ${MAKEOPTS} && \
    make ${MAKEOPTS} install_sw && \
    make clean && \
    ./Configure ${OPENSSL_CONFIG} --cross-compile-prefix=${WIN64}- --prefix=/usr/${WIN64} --openssldir=/usr/${WIN64} mingw64 && \
    make ${MAKEOPTS} && \
    make ${MAKEOPTS} install_sw && \
    cd .. && \
    rm -rf ${OPENSSL}

# openssl linux
RUN cd /usr/src && \
    tar -xzf ${OPENSSL}.tar.gz && \
    cd /usr/src/${OPENSSL} && \
    ./Configure ${OPENSSL_CONFIG} linux-x86_64 --debug --prefix=/usr --openssldir=/usr && \
    make ${MAKEOPTS} && \
    make ${MAKEOPTS} install_sw && \
    make clean && \
    cd .. && \
    rm -rf ${OPENSSL}

# regex windows
RUN cd /usr/src && \
    wget https://downloads.sourceforge.net/mingw/Other/UserContributed/regex/mingw-regex-2.5.1/mingw-libgnurx-2.5.1-src.tar.gz && \
    tar -xvzf mingw-libgnurx-2.5.1-src.tar.gz && \
    cd mingw-libgnurx-2.5.1 && \
    cp ../mingw32-libgnurx-Makefile.am Makefile.am && \
    cp ../mingw32-libgnurx-configure.ac configure.ac && \
    touch NEWS && \
    touch AUTHORS && \
    libtoolize --copy && \
    aclocal && \
    autoconf && \
    automake --add-missing && \
    mkdir build-win32 && \
    cd build-win32 && \
    ../configure --prefix=/usr/i686-w64-mingw32/ --host=i686-w64-mingw32 && \
    make ${MAKEOPTS} && \
    make install && \
    cd .. && \
    mkdir build-win64 && \
    cd build-win64 && \
    ../configure --prefix=/usr/x86_64-w64-mingw32/ --host=x86_64-w64-mingw32 && \
    make ${MAKEOPTS} && \
    make install && \
    cd ..


# install additional linux 64bit dependencies
RUN apt-get -y --no-install-recommends install \
	libdbus-1-dev \
	libudev-dev \
	libgl1-mesa-dev \
	libglu1-mesa-dev \
	mesa-common-dev; \
        rm -rf /var/lib/apt/lists/*

# openssl osx
RUN cd /usr/src && \
    tar -xzf ${OPENSSL}.tar.gz && \
    cd /usr/src/${OPENSSL} && \
    RANLIB=${OSXCROSS}/bin/${OSX32}-ranlib ./Configure ${OPENSSL_CONFIG} no-shared --cross-compile-prefix=${OSXCROSS}/bin/${OSX32}- --prefix=/usr/${OSX32} --openssldir=/usr/${OSX32}/ darwin-i386-cc && \
    make ${MAKEOPTS} && \
    make ${MAKEOPTS} install_sw && \
    make clean && \
    RANLIB=${OSXCROSS}/bin/${OSX64}-ranlib ./Configure ${OPENSSL_CONFIG} no-shared --cross-compile-prefix=${OSXCROSS}/bin/${OSX64}- --prefix=/usr/${OSX64} --openssldir=/usr/${OSX64}/ darwin64-x86_64-cc && \
    make ${MAKEOPTS} && \
    make ${MAKEOPTS} install_sw && \
    make clean 


RUN cd /usr/src/${OPENSSL} && \
    rm -rf ${OSXSDK}/usr/include/openssl && \
    rm -f ${OSXSDK}/usr/lib/libcrypto.* && \
    rm -f ${OSXSDK}/usr/lib/libssl.* && \
    cp -r /usr/${OSX32}/include/openssl ${OSXSDK}/usr/include && \
    cd ${OSXSDK}/usr/include/openssl && \
    patch -p1 -i /usr/src/osxcross-dual-arch-opensslconf.h.patch && \
    cd ${OSXSDK}/usr/lib && \
    ${OSXCROSS}/bin/${OSX64}-libtool -static /usr/${OSX32}/lib/libcrypto.a /usr/${OSX64}/lib/libcrypto.a -o ${OSXSDK}/usr/lib/libcrypto.a && \
    ${OSXCROSS}/bin/${OSX64}-libtool -static /usr/${OSX32}/lib/libssl.a /usr/${OSX64}/lib/libssl.a -o ${OSXSDK}/usr/lib/libssl.a
    

