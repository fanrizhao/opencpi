#!/bin/sh
trap "trap - ERR; return" ERR
set -e

if test "$OCPI_BASE_DIR" != ""; then
  echo Since OCPI_BASE_DIR is set, we will use the existing environment.
  if test "$1" != ""; then
   if "$1" != "$OCPI_TARGET_PLATFORM"; then
      echo Error: supplied platform $1 is different from the environment: $OCPI_TARGET_PLATFORM
      exit 1
   fi
  fi
else
  # We're being run in an uninitialized environment
  if test ! -d env -o ! -d platforms; then
    echo It appears that this script is not being run at the top level of OpenCPI.
    exit 1
  fi
  if test "$1" != ""; then
    echo Supplied cross-platform is $1.
    if test -d platforms/$1; then
     source env/default-cross.sh $1
     test $? = 0 || exit 1; 
    else
     echo Error: $1 is not a supported platform.
     exit 1
    fi
  else
    source env/default-env.sh
    test $? = 0 || exit 1; 
  fi
fi
if test $OCPI_TOOL_HOST = $OCPI_TARGET_HOST; then
  echo ================================================================================
  echo Installing the standard packages for $OCPI_TOOL_PLATFORM.
   platforms/$OCPI_TOOL_PLATFORM/$OCPI_TOOL_PLATFORM-packages.sh
  echo ================================================================================
  echo All basic prerequisites are installed in the system.
fi
if test -d /opt/opencpi/prerequisites; then
  echo The /opt/opencpi directory is already created.
else
  echo We will create /opt/opencpi and make it read/write for everyone
  sudo mkdir -p /opt/opencpi
  sudo chmod a+rwx /opt/opencpi
  mkdir -p /opt/opencpi/prerequisites
fi
echo ================================================================================
echo We are running in `pwd` where the git clone of opencpi has been placed.
echo Next, before building OpenCPI, we will install some prerequisites in /opt/opencpi.
echo ================================================================================
echo Installing Google test '(gtest)' under /opt/opencpi/prerequisites
scripts/install-gtest.sh
echo ================================================================================
echo All OpenCPI prerequisites have been installed.