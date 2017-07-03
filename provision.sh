#!/bin/sh

apk add --update --no-cache opus-dev libsodium-dev ffmpeg build-base
gem install bundler
cd /srv && bundle install
apk del build-base linux-headers pcre-dev openssl-dev
rm -rf /var/cache/apk/*