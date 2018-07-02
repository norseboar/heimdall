FROM ubuntu:18.04

ENV APT_INSTALL_OPTIONS="-y --no-install-recommends"

# Python
RUN apt-get update && apt-get install $APT_INSTALL_OPTIONS \
    python3 python3-pip python3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN pip3 install gunicorn setuptools wheel

ADD requirements.txt .
RUN pip3 install -r requirements.txt

# Needed for python3 + Click, see http://click.pocoo.org/5/python3/
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN mkdir /src
WORKDIR /src
ADD ./webapp /src/

# Configure a user so we're not running as root
RUN useradd -ms /bin/bash heimdall
USER heimdall

# Run the app
ADD entrypoint.sh /src/entrypoint.sh
CMD /src/entrypoint.sh 0.0.0.0:$PORT
