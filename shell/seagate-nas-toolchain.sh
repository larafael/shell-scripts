# arm-linux-gnueabi-gcc -march=armv6k -Wl,-z,max-page-size=0x10000,-z,common-page-size=0x10000,-Ttext-segment=0x10000 main.c -o hello
#!/bin/bash
#
# maketoolchain
#
# Script to build GCC toolchain for Seagate Central NAS
# using open source code.
#
# Supply optional arguments 0 to disable various build stages.
#
# Tested to work on Ubuntu 14.04 after replacing current texinfo with
# version 4.13 from:
# https://launchpad.net/ubuntu/saucy/amd64/texinfo/4.13a.dfsg.1-10ubuntu4

build=i686-pc-linux-gnu
host=$build
export TARGET=arm-vz-linux-gnueabi
linux_arch=arm
export ARCH=arm
export CROSS_COMPILE=${TARGET}-

# see https://gcc.gnu.org/bugzilla/show_bug.cgi?id=14654
export _POSIX2_VERSION=199209

binutilsv=binutils-2.22
gccv=gcc-4.4-2010q1-mv
linuxv=linux
GLIBC=glibc-2.11-2010q1-mvl6

# you can choose different directories here
TOP=$(pwd)/cross
SRC=$(pwd)/src

OBJ=$TOP/obj
TOOLS=$TOP/tools

export SYSROOT=$TOP/sysroot
export PATH=$TOOLS/bin:$PATH

unset LD_LIBRARY_PATH 

mkdir -p $OBJ
mkdir -p $TOOLS
mkdir -p $SYSROOT

ZIPSRC=seagate-central-firmware-gpl-source-code.zip
if [ ! -d $SRC/$gccv ]; then
   echo "Please copy $gccv to $SRC/$gccv"
   echo "$gccv is included in GPL/gcc/gcc.tar in $ZIPSRC"
   exit 1
fi

if [ ! -d $SRC/$linuxv ]; then
   echo "Please copy $linuxv to $SRC/$linuxv"
   echo "$linuxv is included in GPL/linux/git_<...>.tar.gz in $ZIPSRC"
   exit 1
fi

if [ ! -d $SRC/$GLIBC ]; then
   echo "Please copy $GLIBC to $SRC/$GLIBC"
   echo "$GLIBC is included in LGPL/glibc/glibc.tar in $ZIPSRC"
   exit 1
fi

if [ ! -d $SRC/$GLIBC ]; then
   echo "Please copy $GLIBC to $SRC/$GLIBC"
   echo "$GLIBC is included in LGPL/glibc/glibc.tar in $ZIPSRC"
   exit 1
fi

if [ ! -d $SRC/$GLIBC/ports ]; then
   echo "Please link $SRC/$GLIBC/ports to glibc-ports"
   echo "glibc-ports is included in LGPL/glibc/glibc_ports.tar in $ZIPSRC"
   echo "after extracting glibc_ports.tar to $SRC"
   echo "run"
   echo "ln -s ../glibc-ports-2.11-2010q1-mvl6/ $SRC/$GLIBC/ports"
   exit 1
fi

echo
echo "Building $TARGET toolchain in $TOOLS"
echo "sysroot is $SYSROOT"
echo
echo "Reference: Cross-Compiling EGLIBC by Jim Blandy <jimb@codesourcery.com>"
echo "           in $SRC/$GLIBC/EGLIBC.cross-building"
echo

#report error.  4 arguments. 
# $1-retval (0 means success)  $2-name $3-log file $4-cont. on fail (optional)
checkerr()
{
  local GRN="\e[32m"
  local RED="\e[31m"
  local YEL="\e[33m"
  local NOCOLOR="\e[0m"

  if [ $1 -ne 0 ]; then
    echo -e "$RED Failure: $2. Check $3 $NOCOLOR"
    tail $3
    if [ ${4-1} -eq 1 ]; then
      echo -e "$YEL           trying to continue $NOCOLOR"
    else
      exit 1
    fi
  else
    echo -e "$GRN Success: $2.$NOCOLOR See $3"
  fi
}

if [[ $1 != 0 ]]; then
  ### BINUTILS
  mkdir -p $SRC
  cd $SRC

  if [ ! -d $binutilsv ]; then
     wget -nc http://mirror.anl.gov/pub/gnu/binutils/$binutilsv.tar.bz2
     bunzip2 $binutilsv.tar.bz2
     tar -xvf $binutilsv.tar
  fi

  mkdir -p $OBJ/binutils
  cd $OBJ/binutils

  $SRC/$binutilsv/configure --target=$TARGET --prefix=$TOOLS \
    --with-sysroot=$SYSROOT --disable-werror &> $TOP/config_binutils.log
  checkerr $? "config binutils" $TOP/config_binutils.log

  make -j8 &> $TOP/make_binutils.log
  checkerr $? "make binutils" $TOP/make_binutils.log

  make install &> $TOP/make_binutils_install.log
  checkerr $? "install binutils" $TOP/make_binutils_install.log
fi

if [[ $2 != 0 ]]; then
  ### THE FIRST GCC
  mkdir -p $OBJ/gcc1
  cd $OBJ/gcc1

  $SRC/$gccv/configure \
    --target=$TARGET \
    --prefix=$TOOLS \
    --without-headers --with-newlib \
    --disable-shared --disable-threads --disable-libssp \
    --disable-libgomp --disable-libmudflap \
    --enable-languages=c &> $TOP/config_gcc1.log
  checkerr $? "config 1st GCC" $TOP/config_gcc1.log

  make -j8 &> $TOP/make_gcc1.log
  checkerr $? "make 1st GCC" $TOP/make_gcc1.log

  make install &> $TOP/make_gcc1_install.log
  checkerr $? "install 1st GCC" $TOP/make_gcc1_install.log
fi

if [[ $3 != 0 ]]; then
  ### LINUX KERNEL HEADERS
  cp -r $SRC/$linuxv $OBJ/linux
  cd $OBJ/linux
  make headers_install ARCH=$linux_arch CROSS_COMPILE=$TARGET- \
       INSTALL_HDR_PATH=$SYSROOT/usr &> $TOP/make_linux_hdr_install.log
  checkerr $? "install Linux headers" $TOP/make_linux_hdr_install.log
fi

if [[ $4 != 0 ]]; then
  ### EGLIBC Headers and Preliminary Objects
  cd $SRC/$GLIBC/
  mkdir -p $OBJ/eglibc-headers
  cd $OBJ/eglibc-headers
  libc_cv_broken_visibility_attribute=no \
  BUILD_CC=gcc \
  CC=$TOOLS/bin/$TARGET-gcc \
  CXX=$TOOLS/bin/$TARGET-g++ \
  AR=$TOOLS/bin/$TARGET-ar \
  RANLIB=$TOOLS/bin/$TARGET-ranlib \
  $SRC/$GLIBC/configure \
      --prefix=/usr \
      --with-headers=$SYSROOT/usr/include \
      --build=$build \
      --host=$TARGET \
      --disable-profile --without-gd --without-cvs --enable-add-ons \
      &> $TOP/config_eglibc1.log
  checkerr $? "config 1st GLIBC" $TOP/config_eglibc1.log

  make -j8 cross-compiling=yes install_root=$SYSROOT install-headers \
     install-bootstrap-headers=yes &> $TOP/make_eglibc_hdr1.log
  checkerr $? "make 1st GLIBC" $TOP/make_eglibc_hdr1.log

  mkdir -p $SYSROOT/usr/lib
  make csu/subdir_lib &> $TOP/make_eglibc_csu1.log
  checkerr $? "make 1st GLIBC csu" $TOP/make_eglibc_csu1.log
  
  cp csu/crt1.o csu/crti.o csu/crtn.o $SYSROOT/usr/lib
  $TOOLS/bin/$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $SYSROOT/usr/lib/libc.so
fi

if [[ $5 != 0 ]]; then
  ### The Second GCC
  mkdir -p $OBJ/gcc2
  cd $OBJ/gcc2
  $SRC/$gccv/configure \
      --target=$TARGET \
      --prefix=$TOOLS \
      --with-sysroot=$SYSROOT \
      --with-headers=$SYSROOT/usr/include \
      --disable-libssp --disable-libgomp --disable-libmudflap \
      --enable-languages=c \
      &> $TOP/config_gcc2.log
  checkerr $? "config 2nd GCC" $TOP/config_gcc2.log

  make -j8 &> $TOP/make_gcc2.log
  checkerr $? "make 2nd GCC" $TOP/make_gcc2.log

  make install &> $TOP/make_gcc2_install.log
  checkerr $? "install 2nd GCC" $TOP/make_gcc2_install.log
fi

if [[ $6 != 0 ]]; then
  ### EGLIBC, Complete
  mkdir -p $OBJ/eglibc
  cd $OBJ/eglibc
  libc_cv_broken_visibility_attribute=no \
  libc_cv_ssp=no \
  BUILD_CC=gcc \
  CC=$TOOLS/bin/$TARGET-gcc \
  CXX=$TOOLS/bin/$TARGET-g++ \
  AR=$TOOLS/bin/$TARGET-ar \
  RANLIB=$TOOLS/bin/$TARGET-ranlib \
  $SRC/$GLIBC/configure \
      --prefix=/usr \
      --with-headers=$SYSROOT/usr/include \
      --build=$build \
      --host=$TARGET \
      --disable-profile --without-gd --without-cvs --enable-add-ons \
        &> $TOP/config_eglibc2.log

  checkerr $? "config complete GLIBC" $TOP/config_eglibc2.log

  make -j8 &> $TOP/make_eglibc2.log
  checkerr $? "make complete GLIBC" $TOP/make_eglibc2.log

  # last line of cross/obj/eglibc/posix/getconf.speclist has space instead of newline?

  make install_root=$SYSROOT install &> $TOP/make_eglibc2_install.log
  checkerr $? "install complete GLIBC" $TOP/make_eglibc2_install.log 1
fi

if [[ $7 != 0 ]]; then
  ### The Third GCC
  mkdir -p $OBJ/gcc3

  cd $OBJ/gcc3

  $SRC/$gccv/configure \
      --target=$TARGET \
      --prefix=$TOOLS \
      --with-sysroot=$SYSROOT \
      --enable-__cxa_atexit \
      --disable-libssp --disable-libgomp --disable-libmudflap \
      --enable-languages=c,c++ \
  &> $TOP/config_gcc3.log
  checkerr $? "config 3rd (final) GCC" $TOP/config_gcc3.log

  make -j8 &> $TOP/make_gcc3.log
  checkerr $? "make 3rd (final) GCC" $TOP/make_gcc3.log

  make install &> $TOP/make_gcc3_install.log
  checkerr $? "install 3rd (final) GCC" $TOP/make_gcc3_install.log
fi

cp -d $TOOLS/$TARGET/lib/libgcc_s.so* $SYSROOT/lib
cp -d $TOOLS/$TARGET/lib/libstdc++.so* $SYSROOT/usr/lib
