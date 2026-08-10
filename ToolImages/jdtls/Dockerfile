# jdtls — Eclipse's Java language server — and the JDK it is a program in.
#
# This is the image the editor starts when a project names it for `jdtls`, and
# it is what the tool catalogue's contract describes: the server on the entry
# point, speaking the protocol on standard input and output, saying nothing
# before the first header, with the project mounted at /workspace.
#
# On a JDK image because jdtls is not a program that needs a Java toolchain
# nearby, it is a Java program: an Eclipse workspace with the OSGi runtime
# under it. A JRE is not enough — it compiles the project, so it wants the
# compiler — and 21 rather than 17 because the server itself refuses to start
# on less.
#
# This is also the image that most earns the whole feature. `brew install
# jdtls` is a JDK, a 300-megabyte Eclipse bundle and a `JAVA_HOME` to get
# right, and it is the install the editor most often finds missing.
FROM eclipse-temurin:21-jdk-noble

# python3 is the launcher. `bin/jdtls` in the bundle is a Python script that
# works out which OSGi configuration this architecture wants — `config_linux`
# or `config_linux_arm` — and assembles a `java` command line of about twenty
# arguments. Writing that command line out here instead would be maintaining a
# copy of it, and it is the part that differs per architecture, which is the
# one thing a multi-architecture image must not get wrong.
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends python3 curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# Pinned to a milestone, both halves of it: Eclipse's download names carry a
# build timestamp as well as a version, and there is no "latest" that stays
# still. The version is a decision about which answers a project gets, and this
# is the place to say which one.
ARG JDTLS_VERSION=1.55.0
ARG JDTLS_BUILD=202601131729
RUN mkdir --parents /opt/jdtls \
	&& curl --fail --silent --show-error --location \
		"https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_BUILD}.tar.gz" \
	| tar --extract --gzip --directory /opt/jdtls
ENV PATH="/opt/jdtls/bin:${PATH}"

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
#
# Two things this image does not carry, because they are on this machine and a
# path here names nothing in there — `LanguageServers.initializationOptions`
# leaves both out when the server is in a container, and this is the other end
# of that decision. The JDKs a project might target: there is one in here, the
# one above, so a project asking for 17 is compiled against 21. And the
# java-debug bundle, so there is no debugging through this image at all.
WORKDIR /workspace

# No arguments, and in particular no `-data`. The editor gives an image none —
# what it would add for an installed copy is a directory on this machine — and
# the launcher's own default is a directory per working directory inside the
# container, which is exactly right: the index is derived from the project and
# is thrown away with the container.
ENTRYPOINT ["jdtls"]
