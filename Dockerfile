####################################################################################################
# Builder image
# Initial stage which pulls prepares build dependencies and CLI tooling we need for our final image
# Also used as the image in CI jobs so needs all dependencies
####################################################################################################
FROM golang:1.11.13 as builder

RUN apt-get update && apt-get install -y \
    git \
    make \
    wget \
    gcc \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /tmp

# Install docker
ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 18.09.1
RUN wget -O docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/aarch64/docker-${DOCKER_VERSION}.tgz" && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ && \
    rm docker.tgz

# Install dep
ENV DEP_VERSION=0.5.4
RUN wget https://github.com/golang/dep/releases/download/v${DEP_VERSION}/dep-linux-arm64 -O /usr/local/bin/dep && \
    chmod +x /usr/local/bin/dep

# Install golangci-lint
ENV GOLANGCI_LINT_VERSION=1.20.1
RUN curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/v$GOLANGCI_LINT_VERSION/install.sh| sh -s -- -b $(go env GOPATH)/bin v$GOLANGCI_LINT_VERSION

# Install gometalinter
# Keep gometalinter to avoid CI failures during the linter migration.
# We can remove it after enough time has passed.
ENV GOMETALINTER_VERSION=2.0.12
RUN curl -sLo- https://github.com/alecthomas/gometalinter/releases/download/v${GOMETALINTER_VERSION}/gometalinter-${GOMETALINTER_VERSION}-linux-arm64.tar.gz | \
    tar -xzC "$GOPATH/bin" --exclude COPYING --exclude README.md --strip-components 1 -f- && \
    ln -s $GOPATH/bin/gometalinter $GOPATH/bin/gometalinter.v2

####################################################################################################
# Argo Build stage which performs the actual build of Argo binaries
####################################################################################################
FROM builder as argo-build

# A dummy directory is created under $GOPATH/src/dummy so we are able to use dep
# to install all the packages of our dep lock file
COPY Gopkg.toml ${GOPATH}/src/dummy/Gopkg.toml
COPY Gopkg.lock ${GOPATH}/src/dummy/Gopkg.lock

RUN cd ${GOPATH}/src/dummy && \
    dep ensure -vendor-only && \
    mv vendor/* ${GOPATH}/src/ && \
    rmdir vendor

# Perform the build
WORKDIR /go/src/github.com/argoproj/argo
COPY . .
ARG MAKE_TARGET="controller executor cli-linux-arm64"
RUN make $MAKE_TARGET

