FROM fedora:latest
LABEL maintainer="Xiaofeng Wang" \
      email="xiaofwan@redhat.com" \
      baseimage="Fedora:latest" \
      description="Kernel CI multi function image"

# pipenv needs LANG and LC_ALL
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 DATADIR=/kernels NFSDIR=/kernels/nfs AUTHORIZED_KEYS_FILE=/authorized_keys USERID=33 GROUPID=33 OWNER=data

RUN dnf -y update \
      && dnf -y install which python3-pip openssh-server openssh-clients rssh \
      && dnf clean all \
      && pip3 install pipenv \
      && rm -f /etc/ssh/ssh_host_* \
      && chmod a+x /usr/bin/rssh \
      && groupadd --non-unique --gid $GROUPID data \
      && useradd --non-unique --uid $USERID --gid $GROUPID --no-create-home --home-dir $DATADIR --shell /usr/bin/rssh $OWNER \
      && mkdir -p "$NFSDIR" \
      && chown $OWNER "$DATADIR" \
      && sed -i '/AuthorizedKeysFile/d' /etc/ssh/sshd_config \
      && echo "AuthorizedKeysFile $AUTHORIZED_KEYS_FILE" >>/etc/ssh/sshd_config \
      && echo "KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1" >>/etc/ssh/sshd_config \
      && touch $AUTHORIZED_KEYS_FILE \
      && chown $OWNER $AUTHORIZED_KEYS_FILE \
      && chmod 0600 $AUTHORIZED_KEYS_FILE \
      && mkdir /var/run/sshd && chmod 0755 /var/run/sshd \
      && echo "allowscp" >> /etc/rssh.conf \
      && echo "allowsftp" >> /etc/rssh.conf

EXPOSE 22

COPY . /app
WORKDIR /app
RUN pipenv install --system --deploy --ignore-pipfile

COPY entrypoint.sh /
CMD ["/entrypoint.sh"]
