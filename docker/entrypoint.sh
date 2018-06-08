#!/bin/bash

ssh-keygen -A

# Copy authorized keys from ENV variable
echo "$AUTHORIZED_KEYS" >$AUTHORIZED_KEYS_FILE

# Chown data folder (if mounted as a volume for the first time)
chown "${OWNER}:data" "$DATADIR"
chown "${OWNER}:data" $AUTHORIZED_KEYS_FILE

# Run sshd on container start
exec /usr/sbin/sshd -D -e
