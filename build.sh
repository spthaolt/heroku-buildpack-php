#!/bin/bash
set -uex
DIRBASE=`pwd`
DIRAPP=$DIRBASE/app
DIRBUILD=$DIRBASE/build

# Take care of vendoring libmcrypt
mcrypt_version=2.5.8
mcrypt_dirname=libmcrypt-$mcrypt_version
mcrypt_archive_name=$mcrypt_dirname.tar.bz2
# Take care of vendoring Apache.
httpd_version=2.2.27
httpd_dirname=httpd-$httpd_version
httpd_archive_name=$httpd_dirname.tar.bz2
# Take care of vendoring PHP.
php_version=5.3.27
php_dirname=php-$php_version
php_archive_name=$php_dirname.tar.bz2

if [[ ! -d $DIRBUILD ]]; then
  rm -rf $DIRBUILD
  mkdir $DIRBUILD
fi

if [ $# -ne 0 ]; then
    if [[ "$1" == "clean" ]]; then
      cd $DIRBUILD
      rm -rf ./*
    fi
fi

cd $DIRBUILD

# Heroku revision.  Must match in 'compile' program.
#
# Affixed to all vendored binary output to represent changes to the
# compilation environment without a change to the upstream version,
# e.g. PHP 5.3.27 without, and then subsequently with, libmcrypt.
heroku_rev='-2'

# Clear /app directory
find $DIRAPP -mindepth 1 -print0 | xargs -0 rm -rf

# Download mcrypt if necessary
if [ ! -f $mcrypt_archive_name ]
then
    curl -Lo $mcrypt_archive_name http://sourceforge.net/projects/mcrypt/files/Libmcrypt/2.5.8/libmcrypt-2.5.8.tar.bz2/download
fi

# Clean and extract mcrypt
tar jxf $mcrypt_archive_name

# Build and install mcrypt.
pushd $mcrypt_dirname
./configure --prefix=/app/vendor/mcrypt \
  --disable-posix-threads --enable-dynamic-loading
make -s
make install -s DESTDIR=$DIRBASE
popd

# Download Apache if necessary.
if [ ! -f $httpd_archive_name ]
then
    curl -LO ftp://ftp.osuosl.org/pub/apache/httpd/$httpd_archive_name
fi

# Clean and extract Apache.
tar jxf $httpd_archive_name

# Build and install Apache.
pushd $httpd_dirname
./configure --prefix=/app/apache --enable-rewrite --with-included-apr
make -s
make install -s DESTDIR=$DIRBASE
popd

# Download PHP if necessary.
if [ ! -f $php_archive_name ]
then
    curl -Lo $php_archive_name http://us1.php.net/get/php-5.3.27.tar.bz2/from/www.php.net/mirror
fi

# Clean and extract PHP.
tar jxf $php_archive_name

# Compile PHP
pushd $php_dirname
./configure --prefix=/app/php --with-apxs2=/app/apache/bin/apxs     \
--with-mysql --with-pdo-mysql --with-pgsql --with-pdo-pgsql         \
--with-iconv --with-gd --with-curl=/usr/lib                         \
--with-config-file-path=/app/php --enable-soap=shared               \
--with-openssl --with-mcrypt=/app/vendor/mcrypt --enable-sockets
make -s
make install -s DESTDIR=$DIRBASE INSTALL_ROOT=$DIRBASE
popd

# Copy in MySQL client library.
mkdir -p $DIRAPP/php/lib/php
cp /usr/lib/x86_64-linux-gnu/libmysqlclient.so.18 $DIRAPP/php/lib/php

# 'apc' installation
#
# $PATH manipulation Necessary for 'pecl install', which relies on
# PHP binaries relative to $PATH.

export PATH=$DIRAPP/php/bin:$PATH
$DIRAPP/php/bin/pecl channel-update pecl.php.net

# Use defaults for apc build prompts.
#yes '' | $DIRAPP/php/bin/pecl install apc

# Sanitize default cgi-bin to rid oneself of Apache sample
# programs.
find $DIRAPP/apache/cgi-bin/ -mindepth 1 -print0 | xargs -0 rm -r

# Stamp and archive binaries.
pushd $DIRAPP
echo $mcrypt_version > vendor/mcrypt/VERSION
tar -zcf mcrypt-"$mcrypt_version""$heroku_rev".tar.gz vendor/mcrypt
echo $httpd_version > apache/VERSION
tar -zcf apache-"$httpd_version""$heroku_rev".tar.gz apache
echo $php_version > php/VERSION
tar -zcf php-"$php_version""$heroku_rev".tar.gz php
popd
