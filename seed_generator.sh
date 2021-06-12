#!/bin/bash -e

COIN_NAME="Moneta"
COIN_UNIT="MNTA"
#CHAIN="--testnet"
CHAIN=""

SEEDNODE_REPOS=https://github.com/mmontuori/moneta-seeder.git
COIN_NAME_LOWER=$(echo $COIN_NAME | tr '[:upper:]' '[:lower:]')
COIN_NAME_UPPER=$(echo $COIN_NAME | tr '[:lower:]' '[:upper:]')
COIN_UNIT_LOWER=$(echo $COIN_UNIT | tr '[:upper:]' '[:lower:]')
DIRNAME=$(dirname $0)
DOCKER_IMAGE_LABEL="dnsseed-env"
OSVERSION="$(uname -s)"
SEEDNODE_DNS_SERVER="moneta-seed.misas.us"
SEEDNODE_HOST="dnsseed.misas.us"
SEEDNODE_EMAIL="monetaseed@misas.us"

docker_build_image()
{
    IMAGE=$(docker images -q $DOCKER_IMAGE_LABEL)
    if [ -z $IMAGE ]; then
        echo Building docker image
        if [ ! -f $DOCKER_IMAGE_LABEL/Dockerfile ]; then
            mkdir -p $DOCKER_IMAGE_LABEL
            cat <<EOF > $DOCKER_IMAGE_LABEL/Dockerfile
FROM ubuntu:18.04

## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

## preesed tzdata, update package index, upgrade packages and install needed software
RUN truncate -s0 /tmp/preseed.cfg
RUN echo "tzdata tzdata/Areas select America" >> /tmp/preseed.cfg
RUN echo "tzdata tzdata/Zones/America select New_York" >> /tmp/preseed.cfg
RUN debconf-set-selections /tmp/preseed.cfg
RUN rm -f /etc/timezone /etc/localtime
RUN apt update
RUN apt install -y tzdata
RUN apt install -y libterm-readline-gnu-perl
RUN apt -y upgrade
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN apt update
RUN apt install -y apt-utils build-essential libboost-all-dev libssl-dev
EOF
        fi
        docker build --label $DOCKER_IMAGE_LABEL --tag $DOCKER_IMAGE_LABEL $DIRNAME/$DOCKER_IMAGE_LABEL/
    else
        echo Docker image already built
    fi
}


docker_run()
{
    mkdir -p $DIRNAME/.ccache
    docker run -v $DIRNAME/moneta-seeder:/moneta-seeder $DOCKER_IMAGE_LABEL /bin/bash -c "$1"
}

docker_stop_nodes()
{
    echo "Stopping all docker nodes"
    for id in $(docker ps -q -a  -f ancestor=$DOCKER_IMAGE_LABEL); do
        docker stop $id
    done
    echo "y" | docker system prune >/dev/null 2>&1
}

docker_remove_nodes()
{
    echo "Removing all docker nodes"
    for id in $(docker ps -q -a  -f ancestor=$DOCKER_IMAGE_LABEL); do
        docker rm $id
    done
}

docker_run_seednode()
{
    local NODE_COMMAND=$1

    docker run -v $DIRNAME/moneta-seeder:/moneta-seeder --expose 53 --expose 53/udp --publish 53:53 --publish 53:53/udp $DOCKER_IMAGE_LABEL /bin/bash -c "$NODE_COMMAND"
}


build_seednode()
{
    if [ ! -d "moneta-seeder" ]; then
        git clone $SEEDNODE_REPOS
    else
	echo "Updating seeder master branch"
	pushd moneta-seeder
	git pull
	popd
    fi
    docker_run "cd /moneta-seeder ; make -j2"
}


if [ $DIRNAME =  "." ]; then
    DIRNAME=$PWD
fi

cd $DIRNAME

# sanity check

case $OSVERSION in
    Linux*)
        SED=sed
    ;;
    Darwin*)
        SED=$(which gsed 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "please install gnu-sed with 'brew install gnu-sed'"
            exit 1
        fi
        SED=gsed
    ;;
    *)
        echo "This script only works on Linux and MacOS"
        exit 1
    ;;
esac


if ! which docker &>/dev/null; then
    echo Please install docker first
    exit 1
fi

if ! which git &>/dev/null; then
    echo Please install git first
    exit 1
fi

case $1 in
    stop)
        docker_stop_nodes
    ;;
    remove_nodes)
        docker_stop_nodes
        docker_remove_nodes
    ;;
    clean_up)
        docker_stop_nodes
        docker_remove_nodes
        rm -rf moneta-seeder
        rm -rf dnsseed-env
    ;;
    prepare)
        docker_build_image
	build_seednode
    ;;	
    start)
        if [ -n "$(docker ps -q -f ancestor=$DOCKER_IMAGE_LABEL)" ]; then
            echo "There are nodes running. Please stop them first with: $0 stop"
            exit 1
        fi
        docker_run_seednode "/moneta-seeder/dnsseed $CHAIN -h $SEEDNODE_HOST -n $SEEDNODE_DNS_SERVER -m $SEEDNODE_EMAIL >/var/log/dnsseed.log 2>&1" &
    ;;
    *)
        cat <<EOF
Usage: $0 (start|stop|remove_nodes|clean_up)
 - prepare: bootstrap environment and build
 - start: run your new coin
 - stop: simply stop the containers without removing them
 - remove_nodes: remove the old docker container images. This will stop them first if necessary.
 - clean_up: WARNING: this will stop and remove docker containers and network, source code, genesis block information and nodes data directory. (to start from scratch)
EOF
    ;;
esac
