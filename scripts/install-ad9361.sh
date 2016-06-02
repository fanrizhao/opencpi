#!/bin/sh
################################################################################
# Import and prepare the ADI "no_OS" library for using the ad9361 with OpenCPI
# We build the C code into an external library to incorporate into proxies.
# We also derive the xml properties file from the ADI headers.
# The API headers need some tweaks to not introduce bad namespace pollution
# Priorities are:
#   Allow use of their API to program the device
#   Try not to touch their SW at all.
#   Enable repeated installation, refresh etc.
#   Support host and cross compilation
#   Be similar to all other such prereq/import/cross-compilations
set -e
OCPI_AD9361_VERSION=master
source scripts/setup-install.sh
mkdir -p ad9361
cd ad9361
rm -r -f no-OS
################################################################################
# 1. Retrieve/clone the current git repo for the no-OS software
################################################################################
git clone https://github.com/analogdevicesinc/no-OS.git
(cd no-OS; git checkout $OCPI_AD9361_VERSION)

################################################################################
# 2. Generate the xml properties from their header file
################################################################################
T=/tmp/$(basename $0).$$
in=no-OS/ad9361/sw/ad9361.h
mkdir -p include
grep -s '`' $in && {
  echo unexpected backquote character in input: $in
  exit 1
}
# Extract the into from their header file
sed < no-OS/ad9361/sw/ad9361.h -n 's=^#define REG_\([_a-zA-Z]*\)[	 ]*\(0x[0-9ABCDEF]*\)[ 	]*/\* *\(.*\) \*/ *$=\2`\1`\3`rw`1=p' > $T
grep -s "'" $T && {
  echo unexpected single quote character
  exit 1
}
# Convert to property XML (make the OPS file)
#   Note the readonly and volatile lists are by offset since that is easiest to transcribe
#   from the data sheet (register map reference manual)
#   Default is initial and readable.
#   Override lists for writable (dynamic) and volatile (readonly)
awk < $T -F '`' -v nxt=0 "
  BEGIN { printf \"<properties>\n\"
          volatile=\"0x00E|0x017|0x01E|0x01F|0x037|0x05E|0x05F|0x063|0x064|0x06B|0x06C|0x06D|0x0A7|0x0A8|0x0F3|0x0F4|0x124|0x125|0x126|0x127|0x134|0x135|0x136|0x13C|0x13D|0x12E|0x142|0x144|0x161|0x163|0x19A|0x19B|0x19C|0x19D|0x19E|0x19F|0x1A0|0x1A1|0x1A2|0x1A3|0x1A4|0x1A5|0x1A7|0x1A8|0x1A9|0x1AA|0x1AB|0x1AC|0x244|0x247|0x25E|0x284|0x287|0x29E|0x2B0|0x2B1|0x2B2|0x2B3|0x2B4|0x2B5|0x2B6|0x2B7|0x2B8|0x2B9\"
         writable=\"0xFFF\"         
         }
  {
    n=strtonum(\$1)
    a=tolower(\$2)
    r=\" readable='1'\"
    w=\" initial='1'\"
    if (\$1 ~ volatile) { r=\" volatile='1'\"; w=\"\"}
    if (\$1 ~ writable) w=\" writable='1'\"
    if (n != nxt)
      printf \"  <property name='ocpi_pad_%03x' padding='1' arraylength='%u'/>\n\", nxt, n - nxt
    nxt = n + 1
    printf \"  <property name='%s'%s%s%s description='%s'/>\n\", a, r, w, v, \$3
  }
  END { printf \"</properties>\n\" }
  " > include/ad9361-properties.xml
rm $T

################################################################################
# 3. Compile code into the library
################################################################################
rm -r -f build-$OCPI_TARGET_HOST
mkdir build-$OCPI_TARGET_HOST
cd build-$OCPI_TARGET_HOST
if test "$OCPI_CROSS_HOST" = ""; then
CC=gcc
#macos only CXX="c++ -stdlib=libstdc++"
CXX=c++
LD=c++
AR=ar
else
CC=$OCPI_CROSS_BUILD_BIN_DIR/$OCPI_CROSS_HOST-gcc
CXX=$OCPI_CROSS_BUILD_BIN_DIR/$OCPI_CROSS_HOST-c++
LD=$OCPI_CROSS_BUILD_BIN_DIR/$OCPI_CROSS_HOST-c++
AR=$OCPI_CROSS_BUILD_BIN_DIR/$OCPI_CROSS_HOST-ar
fi
dir=../no-OS/ad9361/sw
# We are not depending on their IP
DEFS=-DAXI_ADC_NOT_PRESENT
SRCNAMES=(ad9361 ad9361_api ad9361_conv)
SRCS=(${SRCNAMES[@]/%/.c})
INCS=(ad9361_api)
# They use "malloc.h" which is non-standard.
echo '#include <stdlib.h>' > malloc.h
################################################################################
# 3. Patch their API header so it actuall acts like an API header
################################################################################
# The API header has terrible namespace pollution
ed $dir/ad9361_api.h <<EOF
/#include.*"util.h"/c
#include <stdint.h>
.
w
EOF
$CC -fPIC -I. -I$dir/platform_generic -I$dir $DEFS -c ${SRCS[@]/#/$dir\/}
$AR -rs libad9361.a ${SRCNAMES[@]/%/.o}

################################################################################
# 4. Install the deliverables:  OPS file, headers and library
################################################################################
mkdir -p $OCPI_PREREQUISITES_INSTALL_DIR/ad9361/$OCPI_TARGET_DIR
ln -f -s `pwd` $OCPI_PREREQUISITES_INSTALL_DIR/ad9361/$OCPI_TARGET_DIR/lib
for i in ${INCS[@]}; do
  ln -f -s `pwd`/$dir/$i.h $OCPI_PREREQUISITES_INSTALL_DIR/ad9361/include/$i.h
done
echo ============= ad9361 library for $OCPI_TARGET_DIR built and installed
