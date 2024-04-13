FROM ubuntu:latest

# Set the DEBIAN_FRONTEND environment variable
ENV DEBIAN_FRONTEND=noninteractive

# Install locales package
RUN apt-get update && apt-get install -y locales

# Generate the en_US.UTF-8 locale
RUN locale-gen en_US.UTF-8

# Set the default locale
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_CTYPE=en_US.UTF-8

# Install necessary packages
RUN apt-get update \
    && apt-get install -y tzdata \
    && ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime \
    && dpkg-reconfigure --frontend noninteractive tzdata \
    && apt-get install -y certbot \
    && apt-get install -y mysql-server \
    && apt-get install -y openssl \
    && apt-get install -y software-properties-common \
    && apt-get install -y tar \
    && apt-get install -y wget \
    && apt-get install -y unzip

# Copy your bash shell script to the Docker image
COPY laemp.sh /

# Make the script executable
RUN chmod +x /laemp.sh

# Set the default command to run bash in interactive mode
CMD ["/bin/bash"]
