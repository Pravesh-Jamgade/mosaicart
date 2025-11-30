FROM ubuntu:20.04

RUN apt-get update && apt-get install -y build-essential make

# Create working directory
WORKDIR /opt

COPY BUSE /opt

# Clone and build BUSE
RUN cd /opt/ \
 && make busexmp
