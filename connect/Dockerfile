FROM rockylinux:9

RUN yum install -y epel-release procps initscripts sudo && crb enable

RUN yum install -y https://cdn.posit.co/connect/2024.11/rstudio-connect-2024.11.0.el9.x86_64.rpm

ENV R_VERSION=4.3.3

RUN yum install -y https://cdn.posit.co/r/rhel-9/pkgs/R-${R_VERSION}-1-1.$(arch).rpm

ENV PYTHON_VERSION=3.12.6

RUN dnf install -y https://cdn.rstudio.com/python/rhel-9/pkgs/python-${PYTHON_VERSION}-1-1.x86_64.rpm && /opt/python/${PYTHON_VERSION}/bin/pip install setuptools 

ENV PYTHON_VERSION=3.9.18

RUN dnf install -y https://cdn.rstudio.com/python/rhel-9/pkgs/python-${PYTHON_VERSION}-1-1.x86_64.rpm


RUN echo 'options(repos="https://p3m.dev/cran/__linux__/rhel9/latest")' > /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site && \
    /opt/R/${R_VERSION}/bin/R -q -e 'install.packages("pak")' && \
    /opt/R/${R_VERSION}/bin/R -q -e 'system(pak::pkg_sysreqs(c("shiny","tidyverse"))$install_scripts)'

RUN useradd -m adminuser && \
    useradd -m user1 && \
    useradd -m user2 && \
    useradd -m user3 && \
    echo "adminuser:adminpw" | chpasswd && \
    echo "user1:user1pw" | chpasswd && \
    echo "user2:user2pw" | chpasswd && \
    echo "user3:user3pw" | chpasswd


RUN yum install python3-pip jq pandoc -y && pip install rsconnect-python

COPY config/rstudio-connect.gcfg /etc/rstudio-connect

COPY scripts/psc-start.sh /usr/local/bin

