FROM fedora:latest
LABEL maintainer="Xiaofeng Wang" \
      email="xiaofwan@redhat.com" \
      baseimage="Fedora:latest" \
      description="Kernel CI multi function image"

# pipenv needs LANG and LC_ALL
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

RUN dnf -y update && dnf -y install which python3-pip && dnf clean all
RUN pip3 install pipenv

COPY . /app
WORKDIR /app

RUN pipenv install --system --deploy --ignore-pipfile
