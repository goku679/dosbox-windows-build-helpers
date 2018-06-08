#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

set_box_memory_size_bytes() {
  if [[ $OSTYPE == darwin* ]]; then
    box_memory_size_bytes=20000000000 # 20G fake it out for now :|
  else
    local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
    box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
  fi
}

# Rather than keeping the versioning logic in the script we can pull it into it's own function
# So it can potentially be used if we needed other version comparisons done later.
# Also, using the logic built into sort seems more robust than a roll-your-own for comparing versions.
ver_comp() {
  [ "${1}" = "${2}" ] || [ "$(printf '%s\n%s' "${1}" "${2}" | sort --version-sort | head -n 1)" == "${1}" ]
}

check_missing_packages () {
  # We will need this later if we don't want to just constantly be grepping the /etc/os-release file
  if [ -z "${VENDOR}" ] && grep -E '(centos|rhel)' /etc/os-release &> /dev/null; then
    # In RHEL this should always be set anyway. But not so sure about CentOS
    VENDOR="redhat"
  fi
  # zeranoe's build scripts use wget, though we don't here...
  local check_packages=('curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'makeinfo' 'g++' 'ed' 'hg' 'pax' 'unzip' 'patch' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'cargo')  
  # autoconf-archive is just for leptonica FWIW
  # I'm not actually sure if VENDOR being set to centos is a thing or not. On all the centos boxes I can test on it's not been set at all.
  # that being said, if it where set I would imagine it would be set to centos... And this contition will satisfy the "Is not initially set"
  # case because the above code will assign "redhat" all the time.
  if [ -z "${VENDOR}" ] || [ "${VENDOR}" != "redhat" ] && [ "${VENDOR}" != "centos" ]; then
    check_packages+=('cmake')
  fi
  # libtool check is wonky...
  if [[ $OSTYPE == darwin* ]]; then
    check_packages+=('glibtoolize') # homebrew special :|
  else
    check_packages+=('libtoolize') # the rest of the world
  fi
  # Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
  for package in "${check_packages[@]}"; do
    hash "$package" &> /dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done
  if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
    if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
  fi
  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo, hg is actually package mercurial if you're missing them): ${missing_packages[*]}"
    echo 'Install the missing packages before running this script.'
    echo "for ubuntu: $ sudo apt-get install subversion curl texinfo g++ bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev mercurial unzip pax nasm gperf autogen bzip2 cargo autoconf-archive -y"
    echo "for gentoo (a non ubuntu distro): same as above, but no g++, no gcc, git is dev-vcs/git, zlib1g-dev is zlib, pkg-config is dev-util/pkgconfig, add ed..."
    echo "for OS X (homebrew): brew install wget cvs hg yasm autogen automake autoconf cmake hg libtool xz pkg-config nasm bzip2 cargo autoconf-archive"
    echo "for debian: same as ubuntu, but also add libtool-bin and ed"
    echo "for RHEL/CentOS: First ensure you have epel repos available, then run $ sudo yum install subversion texinfo mercurial libtool autogen gperf nasm patch unzip pax ed gcc-c++ bison flex yasm automake autoconf gcc zlib-devel cvs bzip2 cargo cmake3 -y"
    echo "for fedora: if your distribution comes with a modern version of cmake then use the same as RHEL/CentOS but replace cmake3 with cmake."
    exit 1
  fi

  export REQUIRED_CMAKE_VERSION="3.0.0"
  for cmake_binary in 'cmake' 'cmake3'; do
    # We need to check both binaries the same way because the check for installed packages will work if *only* cmake3 is installed or
    # if *only* cmake is installed.
    # On top of that we ideally would handle the case where someone may have patched their version of cmake themselves, locally, but if
    # the version of cmake required move up to, say, 3.1.0 and the cmake3 package still only pulls in 3.0.0 flat, then the user having manually
    # installed cmake at a higher version wouldn't be detected.
    if hash "${cmake_binary}"  &> /dev/null; then
      cmake_version="$( "${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '[0-9.\n]' )"
      if ver_comp "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
        export cmake_command="${cmake_binary}"
        break
      else
        echo "your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}"
      fi 
    fi
  done

  # If cmake_command never got assigned then there where no versions found which where sufficient.
  if [ -z "${cmake_command}" ]; then
    echo "there where no appropriate versions of cmake found on your machine."
    exit 1
  else
    # If cmake_command is set then either one of the cmake's is adequate.
    echo "cmake binary for this build will be ${cmake_command}"
  fi

  if [[ ! -f /usr/include/zlib.h ]]; then
    echo "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev] [on redhat/fedora distros: $ yum install zlib-devel]" # XXX do like configure does and attempt to compile and include zlib.h instead?
    sleep 1
  fi

  # doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
  # because of all the trailing lines of stuff
  export REQUIRED_YASM_VERSION="1.2.0"
  yasm_binary=yasm
  yasm_version="$( "${yasm_binary}" --version |sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '[0-9.\n]' )"
  if ! ver_comp "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
    echo "your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
    exit 1
  fi
}


intro() {
  echo `date`
  cat <<EOL
     ##################### Welcome ######################
  Welcome to the dosbox cross-compile builder-helper script.
  Downloads and builds will be installed to directories within $cur_dir
  If this is not ok, then exit now, and cd to the directory where you'd
  like them installed, then run this script again from there.
  NB that once you build your compilers, you can no longer rename/move
  the sandbox directory, since it will have some hard coded paths in there.
  You can, of course, rebuild ffmpeg from within it, etc.
EOL
  if [[ $sandbox_ok != 'y' && ! -d sandbox ]]; then
    echo
    echo "Building in $PWD/sandbox, will use ~ 4GB space!"
    echo
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-4] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -n " '$unknown_opt'"
      done
      echo ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Both Win32 and Win64
  2. Win32 (32-bit only)
  3. Win64 (64-bit only)
  4. Exit
EOF
    echo -n 'Input your choice [1-4]: '
    read compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=multi ;;
  2 ) compiler_flavors=win32 ;;
  3 ) compiler_flavors=win64 ;;
  4 ) echo "exiting"; exit 0 ;;
  * ) clear;  echo 'Your choice was not valid, please try again.'; echo ;;
  esac
}

# made into a method so I don't/don't have to download this script every time if only doing just 32 or just6 64 bit builds...
download_gcc_build_script() {
    local zeranoe_script_name=$1
    rm -f $zeranoe_script_name || exit 1
    curl -4 file://$patch_dir/$zeranoe_script_name -O --fail || exit 1
    chmod u+x $zeranoe_script_name
}

install_cross_compiler() {
  local win32_gcc="cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
  local win64_gcc="cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-gcc"
  if [[ -f $win32_gcc && -f $win64_gcc ]]; then
   echo "MinGW-w64 compilers both already installed, not re-installing..."
   if [[ -z $compiler_flavors ]]; then
     echo "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..."
     compiler_flavors=multi
   fi
   return # early exit just assume they want both, don't even prompt :)
  fi

  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi

  mkdir -p cross_compilers
  cd cross_compilers

    unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
    # pthreads version to avoid having to use cvs for it
    echo "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..."
    echo ""

    # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
    local zeranoe_script_name=mingw-w64-build-r22.local
    local zeranoe_script_options="--gcc-ver=7.1.0 --default-configure --cpu-count=$gcc_cpu_count --pthreads-w32-ver=2-9-1 --disable-shared --clean-build --verbose --allow-overwrite" # allow-overwrite to avoid some crufty prompts if I do rebuilds [or maybe should just nuke everything...]
    if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
      echo "Building win32 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
        sed -i "s/ --enable-secure-api//" $zeranoe_script_name
      fi
      nice ./$zeranoe_script_name $zeranoe_script_options --build-type=win32 || exit 1
      if [[ ! -f ../$win32_gcc ]]; then
        echo "Failure building 32 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
    fi
    if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
      echo "Building win64 x86_64 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      nice ./$zeranoe_script_name $zeranoe_script_options --build-type=win64 || exit 1
      if [[ ! -f ../$win64_gcc ]]; then
        echo "Failure building 64 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
    fi

    # rm -f build.log # left over stuff... # sometimes useful...
    reset_cflags
  cd ..
  echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully..."
  echo `date` # so they can see how long it took :)
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  desired_revision="$3"
  if [ ! -d $to_dir ]; then
    echo "svn checking out to $to_dir"
    if [[ -z "$desired_revision" ]]; then
      svn checkout $repo_url $to_dir.tmp  --non-interactive --trust-server-cert || exit 1
    else
      svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
    fi
    mv $to_dir.tmp $to_dir
  else
    cd $to_dir
    echo "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    cd ..
  fi
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    to_dir=$(basename $repo_url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  fi
  local desired_branch="$3"
  if [ ! -d $to_dir ]; then
    echo "Downloading (via git clone) $to_dir from $repo_url"
    rm -rf $to_dir.tmp # just in case it was interrupted previously...
    git clone $repo_url $to_dir.tmp || exit 1
    # prevent partial checkouts by renaming it only after success
    mv $to_dir.tmp $to_dir
    echo "done git cloning to $to_dir"
    cd $to_dir
  else
    cd $to_dir
    if [[ $git_get_latest = "y" ]]; then
      git fetch # need this no matter what
    else
      echo "not doing git get latest pull for latest code $to_dir"
    fi
  fi

  old_git_version=`git rev-parse HEAD`

  if [[ -z $desired_branch ]]; then
    echo "doing git checkout master"
    git checkout -f master || exit 1 # in case they were on some other branch before [ex: going between ffmpeg release tags]. # -f: checkout even if the working tree differs from HEAD.
    if [[ $git_get_latest = "y" ]]; then
      echo "Updating to latest $to_dir git version [origin/master]..."
      git merge origin/master || exit 1
    fi
  else
    echo "doing git checkout $desired_branch"
    git checkout -f "$desired_branch" || exit 1
    git merge "$desired_branch" || exit 1 # get incoming changes to a branch
  fi

  new_git_version=`git rev-parse HEAD`
  if [[ "$old_git_version" != "$new_git_version" ]]; then
    echo "got upstream changes, forcing re-configure."
    git clean -f # Throw away local changes; 'already_*' and bak-files for instance.
  else
    echo "fetched no code changes, not forcing reconfigure for that..."
  fi
  cd ..
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS $LDFLAGS | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
}

do_autogen() {
  local autogen_name="$1"
  if [[ "$autogen_name" = "" ]]; then
    autogen_name="./autogen.sh"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name autogenned "$autogen_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...

    echo "autogenning $english_name ($PWD) as PATH=$mingw_bin_path:\$PATH $autogen_name" # say it now in case bootstrap fails etc.
    rm -f autogenned_* # reset
    "$autogen_name" || exit 1 # not nice on purpose, so that if some other script is running as nice, this one will get priority :)
    touch -- "$touch_name"
  else
    echo "already autogenned $(basename $cur_dir2)"
  fi
}

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...

    echo "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$mingw_bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
    if [ -f bootstrap ]; then
      ./bootstrap # some need this to create ./configure :|
    fi
    if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
      ./bootstrap.sh
    fi
    if [[ ! -f $configure_name ]]; then
      autoreconf -fiv # a handful of them require this to create ./configure :|
    fi
    rm -f already_* # reset
    "$configure_name" $configure_options || exit 1 # not nice on purpose, so that if some other script is running as nice, this one will get priority :)
    touch -- "$touch_name"
    echo "doing preventative make clean"
    nice make clean -j $cpu_count # sometimes useful when files change, etc.
  #else
  #  echo "already configured $(basename $cur_dir2)"
  fi
}

do_make() {
  local extra_make_options="$1 -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )

  if [ ! -f $touch_name ]; then
    echo
    echo "making $cur_dir2 as $ PATH=$mingw_bin_path:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already made $(basename "$cur_dir2") ..."
  fi
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_install_options"
  else
    local make_install_options="$override_make_install_options $extra_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$mingw_bin_path:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake() {
  extra_args="$1"
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    echo doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:
    echo ${cmake_command} -G"Unix Makefiles" . -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args
    ${cmake_command} -G"Unix Makefiles" . -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_from_build_dir() {
  source_dir="$1"
  extra_args="$2"
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    echo doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:
    echo ${cmake_command} -G"Unix Makefiles" $source_dir -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args
    ${cmake_command} -G"Unix Makefiles" $source_dir -DENABLE_STATIC_RUNTIME=1 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_and_install() {
  do_cmake "$1"
  do_make_and_make_install
}

apply_patch() {
  local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
  local patch_type=$2
  if [[ -z $patch_type ]]; then
    patch_type="-p0" # some are -p1 unfortunately, git's default
  fi
  local patch_name=$(basename $url)
  local patch_done_name="$patch_name.done"
  if [[ ! -e $patch_done_name ]]; then
    if [[ -f $patch_name ]]; then
      rm $patch_name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $url -O --fail || echo_and_exit "unable to download patch file $url"
    echo "applying patch $patch_name"
    patch $patch_type < "$patch_name" || exit 1
    touch $patch_done_name || exit 1
    rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  #else
    #echo "patch $patch_name already applied"
  fi
}

echo_and_exit() {
  echo "failure, exiting: $1"
  exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [[ -z $output_dir ]]; then
    output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url"
    if [[ -f $output_name ]]; then
      rm $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    #  -L means "allow redirection" or some odd :|

    curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    rm "$output_name" || exit 1
  fi
}

generic_configure() {
  local extra_configure_options="$1"
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_configure() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  cd ..
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  cd ..
}

do_git_checkout_and_make_install() {
  local url=$1
  local git_checkout_name=$(basename $url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  do_git_checkout $url $git_checkout_name
  cd $git_checkout_name
    generic_configure_make_install
  cd ..
}

generic_configure_make_install() {
  if [ $# -gt 0 ]; then
    echo "cant pass parameters to this today"
    echo "The following arguments where passed: ${@}"
    exit 1
  fi
  generic_configure # no parameters, force myself to break it up if needed
  do_make_and_make_install
}

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="$2"
  if [[ ! -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a ]]; then
    echo "Generating linker script $lib: $2 $3"
    mv -f $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $3 )" > $lib
  fi
}

reset_cflags() {
  export CFLAGS=$original_cflags
}

find_all_build_exes() {
  local found=""
# NB that we're currently in the sandbox dir...
  for file in `find . -name ffmpeg.exe` `find . -name ffmpeg_g.exe` `find . -name ffplay.exe` `find . -name MP4Box.exe` `find . -name mplayer.exe` `find . -name mencoder.exe` `find . -name avconv.exe` `find . -name avprobe.exe` `find . -name x264.exe` `find . -name writeavidmxf.exe` `find . -name writeaviddv50.exe` `find . -name rtmpdump.exe` `find . -name x265.exe` `find . -name ismindex.exe` `find . -name dvbtee.exe` `find . -name boxdumper.exe` `find . -name muxer.exe ` `find . -name remuxer.exe` `find . -name timelineeditor.exe` `find . -name lwcolor.auc` `find . -name lwdumper.auf` `find . -name lwinput.aui` `find . -name lwmuxer.auf` `find . -name vslsmashsource.dll`; do
    found="$found $(readlink -f $file)"
  done

  # bash recursive glob fails here again?
  for file in `find . -name vlc.exe | grep -- -`; do
    found="$found $(readlink -f $file)"
  done
  echo $found # pseudo return value...
}

build_dependencies() {
  echo "Building dosbox dependency libraries..."
  build_dlfcn
  build_mman
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected.
  build_liblzma # Lzma in FFmpeg is autodetected. Uses dlfcn.
  build_zlib # Zlib in FFmpeg is autodetected.
  build_libjpeg_turbo
  build_libpng # Needs zlib >= 1.0.4. Uses dlfcn.
  build_freeglut
  build_jbigkit
  build_libtiff
  build_lcms
  build_lcms2
  build_libopenjpeg
  build_libmng
#libmng-1.0.10
  build_giflib
  build_libmad
  build_libid3tag
  build_harfbuzz
  build_freetype
  build_imlib2
  build_pixman
  build_iconv
  build_libxml2
  build_fontconfig
  #build_glib120
  build_gettext
  #build_glib214
  build_libcurl
  build_cairo
  build_pcre
  build_libffi
  #build_glib257
  #build_librsvg
  #build_poppler
  #build_cairo
  #build_directfb
  build_libwebp
  build_sdl
  build_sdl_net
  build_sdl_image
  build_smpeg
  build_libmikmod
  build_libmodplug
  build_sdl_sound
}

build_apps() {
  echo "Building dosbox..."
}

build_dlfcn() {
  if [ ! -e dlfcn ]; then
    do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32.git
    cd dlfcn-win32_git
      if [[ ! -f Makefile.bak ]]; then # Change CFLAGS.
        sed -i.bak "s/-O3/-O2/" Makefile
      fi
      do_configure "--prefix=$mingw_w64_x86_64_prefix --cross-prefix=$cross_prefix" # rejects some normal cross compile options so custom here
      do_make_and_make_install
      gen_ld_script libdl.a dl_s -lpsapi # dlfcn-win32's 'README.md': "If you are linking to the static 'dl.lib' or 'libdl.a', then you would need to explicitly add 'psapi.lib' or '-lpsapi' to your linking command, depending on if MinGW is used."
    cd ..
    touch dlfcn
  fi
}

build_mman() {
  if [ ! -e mman ]; then
    do_git_checkout https://github.com/witwall/mman-win32.git
    cd mman-win32_git
      apply_patch file://$patch_dir/mman-win32.configure.patch -p1
      chmod a+x ./configure
      do_configure "--prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static --bindir=$mingw_w64_x86_64_prefix/bin --libdir=$mingw_w64_x86_64_prefix/lib --incdir=$mingw_w64_x86_64_prefix/include/sys"
      do_make_and_make_install "$make_prefix_options"
      do_make_and_make_install "$make_prefix_options install"
    cd ..
    touch mman
  fi
}

build_bzip2() {
  if [ ! -e bzip2 ]; then
    download_and_unpack_file http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
    cd bzip2-1.0.6
      apply_patch file://$patch_dir/bzip2-1.0.6_brokenstuff.diff
      if [[ ! -f $mingw_w64_x86_64_prefix/lib/libbz2.a ]]; then # Library only.
        do_make "$make_prefix_options libbz2.a"
        install -m644 bzlib.h $mingw_w64_x86_64_prefix/include/bzlib.h
        install -m644 libbz2.a $mingw_w64_x86_64_prefix/lib/libbz2.a
      else
        echo "already made bzip2-1.0.6"
      fi
    cd ..
    touch bzip2
  fi
}

build_liblzma() {
  if [ ! -e liblzma ]; then
    download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.2.3.tar.xz
    cd xz-5.2.3
      generic_configure "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls"
      do_make_and_make_install
    cd ..
    touch liblzma
  fi
}

build_zlib() {
  if [ ! -e zlib ]; then
    download_and_unpack_file https://github.com/madler/zlib/archive/v1.2.11.tar.gz zlib-1.2.11
    cd zlib-1.2.11
      do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
      do_make_and_make_install "$make_prefix_options ARFLAGS=rcs" # ARFLAGS Avoid failure in OS X
    cd ..
    touch zlib
  fi
}

build_libjpeg_turbo() {
  if [ ! -e libjpeg_turbo ]; then
    download_and_unpack_file https://sourceforge.net/projects/libjpeg-turbo/files/1.5.0/libjpeg-turbo-1.5.0.tar.gz
    cd libjpeg-turbo-1.5.0
      #do_cmake_and_install "-DNASM=yasm" # couldn't figure out a static only build with cmake...maybe you can these days dunno
      generic_configure "NASM=yasm"
      do_make_and_make_install
      sed -i.bak 's/typedef long INT32/typedef long XXINT32/' "$mingw_w64_x86_64_prefix/include/jmorecfg.h" # breaks VLC build without this...freaky...theoretically using cmake instead would be enough, but that installs .dll.a file... XXXX maybe no longer needed :|
    cd ..
    touch libjpeg_turbo
  fi
}

build_libpng() {
  if [ ! -e libpng ]; then
    download_and_unpack_file https://github.com/glennrp/libpng/archive/v1.6.34.tar.gz libpng-1.6.34
    #do_git_checkout https://github.com/glennrp/libpng.git
    cd libpng-1.6.34
      generic_configure
      do_make_and_make_install
    cd ..
    touch libpng
  fi
}

build_freeglut() {
  if [ ! -e freeglut ]; then
    download_and_unpack_file https://downloads.sourceforge.net/freeglut/freeglut-3.0.0.tar.gz
    #do_git_checkout https://github.com/uclouvain/openjpeg.git # basically v2.3+ 
    cd freeglut-3.0.0
      do_cmake_and_install "-DFREEGLUT_BUILD_SHARED_LIBS=OFF -DFREEGLUT_BUILD_STATIC_LIBS=ON -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=$mingw_w64_x86_64_prefix/bin -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$mingw_w64_x86_64_prefix/lib -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=$mingw_w64_x86_64_prefix/lib -DENABLE_STATIC_RUNTIME=ON -DFREEGLUT_BUILD_DEMOS=OFF"
    cd ..
    touch freeglut
  fi
}

build_jbigkit() {
  if [ ! -e jbigkit ]; then
    download_and_unpack_file http://www.cl.cam.ac.uk/~mgk25/jbigkit/download/jbigkit-2.1.tar.gz
    #do_git_checkout https://github.com/glennrp/libpng.git
    apply_patch file://$patch_dir/jbigkit_makefile.diff
    cd jbigkit-2.1
      do_make "$make_prefix_options lib"
      do_make "$make_prefix_options install"
    cd ..
    touch jbigkit 
  fi
}

build_libtiff() {
  if [ ! -e libtiff ]; then
    build_libjpeg_turbo # auto uses it?
    generic_download_and_make_and_install http://download.osgeo.org/libtiff/tiff-4.0.9.tar.gz
    sed -i.bak 's/-ltiff.*$/-ltiff -llzma -ljbig -ljpeg -lz/' $PKG_CONFIG_PATH/libtiff-4.pc # static deps
    touch libtiff 
  fi
} 

build_lcms() {
  if [ ! -e lcms ]; then
    download_and_unpack_file https://downloads.sourceforge.net/lcms/lcms-1.19.tar.gz

    apply_patch file://$patch_dir/lcms_configfix.diff
    cd lcms-1.19
      generic_configure "--disable-shared --enable-static"
      do_make_and_make_install
    cd ..
    touch lcms
  fi
}

build_lcms2() {
  if [ ! -e lcms2 ]; then
    download_and_unpack_file https://downloads.sourceforge.net/lcms/lcms2-2.9.tar.gz

    apply_patch file://$patch_dir/lcms2_configfix.diff
    cd lcms2-2.9
      generic_configure "--disable-shared --enable-static --with-jpeg=$mingw_w64_x86_64_prefix --with-tiff=$mingw_w64_x86_64_prefix"
      do_make_and_make_install
    cd ..
    touch lcms2
  fi
}

build_libopenjpeg() {
  if [ ! -e libopenjpeg ]; then
    download_and_unpack_file https://github.com/uclouvain/openjpeg/archive/v2.3.0.tar.gz openjpeg-2.3.0
    #do_git_checkout https://github.com/uclouvain/openjpeg.git # basically v2.3+ 
    cd openjpeg-2.3.0
      do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DBUILD_CODEC=0"
    cd ..
    touch libopenjpeg
  fi
}

build_libmng() {
  if [ ! -e libmng ]; then
    download_and_unpack_file https://downloads.sourceforge.net/libmng/libmng-2.0.3.tar.gz
    cd libmng-2.0.3
      generic_configure "--disable-shared --enable-static --with-jpeg=$mingw_w64_x86_64_prefix --with-zlib=$mingw_w64_x86_64_prefix --with-lcms=$mingw_w64_x86_64_prefix --with-lcms2=$mingw_w64_x86_64_prefix"
      do_make_and_make_install
    cd ..
    touch libmng
  fi
}

build_giflib() {
  if [ ! -e giflib ]; then
    download_and_unpack_file https://downloads.sourceforge.net/giflib/giflib-5.1.4.tar.gz
    cd giflib-5.1.4
      generic_configure "--disable-shared --enable-static"
      do_make_and_make_install
    cd ..
    touch giflib
  fi
}

build_libmad() {
  if [ ! -e libmad ]; then
    download_and_unpack_file https://downloads.sourceforge.net/mad/libmad-0.15.1b.tar.gz
    cd libmad-0.15.1b
      generic_configure "--disable-shared --enable-static"
      do_make_and_make_install
    cd ..
    touch libmad
  fi
}

build_libid3tag() {
  if [ ! -e libid3tag ]; then
    download_and_unpack_file https://downloads.sourceforge.net/mad/libid3tag-0.15.1b.tar.gz
    cd libid3tag-0.15.1b
      generic_configure "--disable-shared --enable-static"
      do_make_and_make_install
    cd ..
    touch libid3tag
  fi
}

build_harfbuzz() {
  if [ ! -e harfbuzz ]; then
    download_and_unpack_file https://github.com/harfbuzz/harfbuzz/releases/download/1.7.6/harfbuzz-1.7.6.tar.bz2
    cd libid3tag-0.15.1b
      generic_configure "--disable-shared --enable-static"
      do_make_and_make_install
    cd ..
    touch harfbuzz
  fi
}

build_freetype() {
  download_and_unpack_file https://sourceforge.net/projects/freetype/files/freetype2/2.8/freetype-2.8.tar.bz2
  cd freetype-2.8
    if [[ `uname` == CYGWIN* ]]; then
      generic_configure "--build=i686-pc-cygwin --with-zlib --with-bzip2 --with-png --with-harfbuzz" # hard to believe but needed...
      # 'configure' can't detect bzip2 without '--with-bzip2', because there's no 'bzip2.pc'.
    else
      generic_configure "--with-bzip2"
    fi
    do_make_and_make_install
  cd ..
}

build_imlib2() {
  if [ ! -e imlib2 ]; then
    download_and_unpack_file https://downloads.sourceforge.net/enlightenment/imlib2-1.5.1.tar.bz2
    apply_patch file://$patch_dir/imlib2_configfix.diff
    cd imlib2-1.5.1
      generic_configure "--disable-shared --enable-static --without-x --disable-mmx --disable-amd64 --disable-visibility-hiding"
      do_make_and_make_install
    cd ..
    touch imlib2
  fi
}

build_pixman() {
  if [ ! -e pixman ]; then
    download_and_unpack_file https://www.cairographics.org/releases/pixman-0.34.0.tar.gz
    cd pixman-0.34.0
      generic_configure
      do_make_and_make_install
    cd ..
    touch pixman
  fi
}

build_iconv() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz
  cd libiconv-1.15
    generic_configure "--disable-nls"
    do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  cd ..
}

build_libxml2() {
  download_and_unpack_file http://xmlsoft.org/sources/libxml2-2.9.4.tar.gz libxml2-2.9.4
  cd libxml2-2.9.4
    if [[ ! -f libxml.h.bak ]]; then # Otherwise you'll get "libxml.h:...: warning: "LIBXML_STATIC" redefined". Not an error, but still.
      sed -i.bak "/NOLIBTOOL/s/.*/& \&\& !defined(LIBXML_STATIC)/" libxml.h
    fi
    generic_configure "--with-ftp=no --with-http=no --with-python=no"
    do_make_and_make_install
  cd ..
}

build_fontconfig() {
  download_and_unpack_file https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.12.4.tar.gz
  cd fontconfig-2.12.4
    #export CFLAGS= # compile fails with -march=sandybridge ... with mingw 4.0.6 at least ...
    generic_configure "--enable-iconv --enable-libxml2 --disable-docs --with-libiconv" # Use Libxml2 instead of Expat.
    do_make_and_make_install
    #reset_cflags
  cd ..
}

build_glib120() {
  if [ ! -e glib120 ]; then
    download_and_unpack_file https://download.gnome.org/sources/glib/1.2/glib-1.2.10.tar.gz
    apply_patch file://$patch_dir/glib-1.2.10.diff
    cd glib-1.2.10
      generic_configure
      do_make_and_make_install
    cd ..
    touch glib120 
  fi
}

build_gettext() {
  if [ ! -e gettext ]; then
    download_and_unpack_file https://ftp.gnu.org/pub/gnu/gettext/gettext-0.19.8.tar.gz
    cd gettext-0.19.8
      export CFLAGS="${CFLAGS} -DLIBXML_STATIC"
      generic_configure
      do_make_and_make_install
      reset_cflags
    cd ..
    touch gettext
  fi
}

build_glib214() {
  if [ ! -e glib214 ]; then
    download_and_unpack_file https://download.gnome.org/sources/glib/2.14/glib-2.14.6.tar.gz
    apply_patch file://$patch_dir/glib-2.14.6.diff
    cd glib-2.14.6
      generic_configure
      do_make_and_make_install
    cd ..
    touch glib214
  fi
}

build_libcurl() {
  generic_download_and_make_and_install https://curl.haxx.se/download/curl-7.46.0.tar.gz
}

build_cairo() {
  if [ ! -e cairo ]; then
    download_and_unpack_file https://www.cairographics.org/releases/cairo-1.14.12.tar.xz
    cd cairo-1.14.12
      generic_configure "--enable-tee=yes --enable-xml=yes --enable-fc=yes --enable-ft=yes --enable-script=yes --enable-png=yes --enable-svg=no --enable-pdf=no --enable-ps=no --enable-gobject=no"
      do_make_and_make_install
    cd ..
    touch cairo
  fi
}

build_pcre() {
  if [ ! -e pcre ]; then
    download_and_unpack_file https://ftp.pcre.org/pub/pcre/pcre-8.42.tar.gz
    cd pcre-8.42
      generic_configure "--enable-pcre16 --enable-pcre32 --enable-jit --enable-utf --enable-unicode-properties"
      do_make_and_make_install
    cd ..
    touch pcre 
  fi
}

build_libffi() {
  if [ ! -e libffi ]; then
    download_and_unpack_file https://sourceware.org/ftp/libffi/libffi-3.2.1.tar.gz
    cd libffi-3.2.1
      generic_configure 
      do_make_and_make_install
    cd ..
    touch libffi 
  fi
}

build_glib257() {
  if [ ! -e glib257 ]; then
    download_and_unpack_file https://download.gnome.org/sources/glib/2.57/glib-2.57.1.tar.xz
    apply_patch file://$patch_dir/glib-2.57.1.diff
    cd glib-2.57.1
      generic_configure 
      do_make_and_make_install V=1
    cd ..
    touch glib257 
  fi
}

build_librsvg() {
  if [ ! -e librsvg ]; then
    download_and_unpack_file http://ftp.gnome.org/pub/gnome/sources/librsvg/2.42/librsvg-2.42.2.tar.xz
    cd librsvg-2.42.2
      generic_configure
      do_make_and_make_install
    cd ..
    exit 1
    touch librsvg 
  fi
}

build_poppler() {
  if [ ! -e poppler ]; then
    download_and_unpack_file https://poppler.freedesktop.org/poppler-0.65.0.tar.xz
    cd poppler-0.65.0
      do_cmake_and_install "-DBUILD_SHARED_LIBS=0 -DENABLE_QT5=0"
    cd ..
    exit 1
    touch poppler
  fi
}

#build_cairo() {
#  if [ ! -e cairo ]; then
#    download_and_unpack_file https://www.cairographics.org/releases/cairo-1.14.12.tar.xz
#    cd cairo-1.14.12
#      generic_configure "--enable-tee=yes --enable-xml=yes --enable-gobject=yes --enable-svg=yes --enable-pdf=yes --enable-ps=yes --enable-fc=yes --enable-ft=yes --enable-script=yes --enable-png=yes"
#      do_make_and_make_install
#    cd ..
#    exit 1
#    touch cairo 
#  fi
#}

build_directfb() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  generic_download_and_make_and_install https://src.fedoraproject.org/repo/pkgs/directfb/DirectFB-1.6.3.tar.gz/md5/641e8e999c017770da647f9b5b890906/DirectFB-1.6.3.tar.gz
}

build_libwebp() {
  if [ ! -e webp ]; then
    do_git_checkout https://chromium.googlesource.com/webm/libwebp.git
    cd libwebp_git
      git checkout 84947197be604ab893e86ce96b22111953b69435
      export LIBPNG_CONFIG="$mingw_w64_x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected.
      generic_configure "--disable-wic"
      do_make_and_make_install
      unset LIBPNG_CONFIG
    cd ..
  fi
}

build_sdl() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  export CFLAGS=-DDECLSPEC=  # avoid SDL trac tickets 939 and 282, and not worried about optimizing yet...
#  generic_download_and_configure https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  generic_download_and_make_and_install https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  reset_cflags
  mkdir -p temp
  cd temp # so paths will work out right
  local prefix=$(basename $cross_prefix)
  local bin_dir=$(dirname $cross_prefix)
  sed -i.bak "s/-mwindows//" "$PKG_CONFIG_PATH/sdl.pc" # allow ffmpeg to output anything to console :|
  sed -i.bak "s/Libs:\(.*\)$/Libs:\1-liconv -lm -luser32 -lgdi32 -lwinmm -ldxguid /" "$PKG_CONFIG_PATH/sdl.pc" # allow ffmpeg to output anything to console :|
  sed -i.bak "s/-mwindows//" "$mingw_w64_x86_64_prefix/bin/sdl-config" # update this one too for good measure, FFmpeg can use either, not sure which one it defaults to...
  cp "$mingw_w64_x86_64_prefix/bin/sdl-config" "$bin_dir/${prefix}sdl-config" # this is the only mingw dir in the PATH so use it for now [though FFmpeg doesn't use it?]
  cd ..
  rmdir temp
}

build_sdl_net() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  export CFLAGS=-DDECLSPEC=  # avoid SDL trac tickets 939 and 282, and not worried about optimizing yet...
#  generic_download_and_configure https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  generic_download_and_make_and_install https://www.libsdl.org/projects/SDL_net/release/SDL_net-1.2.8.tar.gz
  reset_cflags
  mkdir -p temp
  cd temp # so paths will work out right
  sed -i.bak "s/-mwindows//" "$PKG_CONFIG_PATH/SDL_net.pc" # allow ffmpeg to output anything to console :|
  cd ..
  rmdir temp
}

build_sdl_image() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  export CFLAGS=-DDECLSPEC=  # avoid SDL trac tickets 939 and 282, and not worried about optimizing yet...
#  generic_download_and_configure https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  download_and_unpack_file https://www.libsdl.org/projects/SDL_image/release/SDL_image-1.2.12.tar.gz
  apply_patch file://$patch_dir/SDL_image-1.2.12.diff
  cd SDL_image-1.2.12
    generic_configure
    do_make_and_make_install
  cd ..
  reset_cflags
  mkdir -p temp
  cd temp # so paths will work out right
  sed -i.bak "s/-mwindows//" "$PKG_CONFIG_PATH/SDL_image.pc" # allow ffmpeg to output anything to console :|
  cd ..
  rmdir temp
}

build_smpeg() {
  do_svn_checkout svn://svn.icculus.org/smpeg/tags/release_0_4_5 smpeg-0.4.5
  apply_patch file://$patch_dir/smpeg-0.4.5.diff
  cd smpeg-0.4.5
    do_autogen
    generic_configure "--enable-gtk-player=no"
    do_make_and_make_install
  cd ..
}

build_libmikmod() {
  download_and_unpack_file https://github.com/sezero/mikmod/archive/libmikmod-3.3.11.1.tar.gz mikmod-libmikmod-3.3.11.1
  cd mikmod-libmikmod-3.3.11.1/libmikmod
    generic_configure
    do_make_and_make_install
  cd ../..
}

build_libmodplug() {
  download_and_unpack_file https://sourceforge.net/projects/modplug-xmms/files/libmodplug-0.8.9.0.tar.gz
  cd libmodplug-0.8.9.0
    generic_configure
    do_make_and_make_install
  cd ..
}

build_sdl_sound() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  export CFLAGS=-DDECLSPEC=  # avoid SDL trac tickets 939 and 282, and not worried about optimizing yet...
#  generic_download_and_configure https://www.libsdl.org/release/SDL-1.2.15.tar.gz
  download_and_unpack_file https://www.icculus.org/SDL_sound/downloads/SDL_sound-1.0.3.tar.gz
  apply_patch file://$patch_dir/SDL_sound-1.0.3.diff
  cd SDL_sound-1.0.3
    export CFLAGS="${CFLAGS} -I$mingw_w64_x86_64_prefix/include -I$mingw_w64_x86_64_prefix/include/smpeg"
    generic_configure
    exit 1
    do_make_and_make_install
    reset_cflags
  cd ..
  mkdir -p temp
  cd temp # so paths will work out right
  sed -i.bak "s/-mwindows//" "$PKG_CONFIG_PATH/SDL_sound.pc" # allow ffmpeg to output anything to console :|
  cd ..
  rmdir temp
}

# set some parameters initial values
cur_dir="$(pwd)/sandbox"
patch_dir="$(pwd)/patches"
cpu_count="$(grep -c processor /proc/cpuinfo 2>/dev/null)" # linux cpu count
if [ -z "$cpu_count" ]; then
  cpu_count=`sysctl -n hw.ncpu | tr -d '\n'` # OS X
  if [ -z "$cpu_count" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi
original_cpu_count=$cpu_count # save it away for some that revert it temporarily

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$cpu_count # they can handle it seemingly...
else
  echo "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

# variables with their defaults
original_cflags='-mtune=generic -O3' # high compatible by default, see #219, some other good options are listed below, or you could use -march=native to target your local box:

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --gcc-cpu-count=[number of cpu cores set it higher than 1 if you have multiple cores and > 1GB RAM, this speeds up initial cross compiler build. FFmpeg build uses number of cores no matter what]
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static with some reasonable defaults like no git updates]
      -a 'build all' builds ffmpeg, mplayer, vlc, etc. with all fixings turned on
      --compiler-flavors=[multi,win32,win64] [default prompt, or skip if you already have one built, multi is both win32 and win64]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --prefer-stable=y build a few libraries from releases instead of git master
      --high-bitdepth=n Enable high bit depth for x264 (10 bits) and x265 (10 and 12 bits, x64 build. Not officially supported on x86 (win32), but enabled by disabling its assembly).
      --debug Make this script  print out each line as it executes
       "; exit 0 ;;
    --gcc-cpu-count=* ) gcc_cpu_count="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    # this doesn't actually "build all", like doesn't build 10 high-bit LGPL ffmpeg, but it does exercise the "non default" type build options...
    -a         ) compiler_flavors="multi"; 
                 shift ;;
    -d         ) gcc_cpu_count=$cpu_count; compiler_flavors="win32"; shift ;;
    --compiler-flavors=* ) compiler_flavors="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]

if [[ $OSTYPE == darwin* ]]; then
  # mac add some helper scripts
  mkdir -p mac_helper_scripts
  cd mac_helper_scripts
    if [[ ! -x readlink ]]; then
      # make some scripts behave like linux...
      curl -4 file://$patch_dir/md5sum.mac --fail > md5sum  || exit 1
      chmod u+x ./md5sum
      curl -4 file://$patch_dir/readlink.mac --fail > readlink  || exit 1
      chmod u+x ./readlink
    fi
    export PATH=`pwd`:$PATH
  cd ..
fi

original_path="$PATH"
if [[ $compiler_flavors == "multi" || $compiler_flavors == "win32" ]]; then
  echo
  echo "Starting 32-bit builds..."
  host_target='i686-w64-mingw32'
  mingw_w64_x86_64_prefix="$cur_dir/cross_compilers/mingw-w64-i686/$host_target"
  mingw_bin_path="$cur_dir/cross_compilers/mingw-w64-i686/bin"
  export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
  export PATH="$mingw_bin_path:$original_path"
  bits_target=32
  cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++ AS=${cross_prefix}as CPP=${cross_prefix}cpp"
  mkdir -p win32
  cd win32
    build_dependencies 
    build_apps
  cd ..
fi

if [[ $compiler_flavors == "multi" || $compiler_flavors == "win64" ]]; then
  echo
  echo "**************Starting 64-bit builds..." # make it have a bit easier to you can see when 32 bit is done
  host_target='x86_64-w64-mingw32'
  mingw_w64_x86_64_prefix="$cur_dir/cross_compilers/mingw-w64-x86_64/$host_target"
  mingw_bin_path="$cur_dir/cross_compilers/mingw-w64-x86_64/bin"
  export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
  export PATH="$mingw_bin_path:$original_path"
  bits_target=64
  cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++ AS=${cross_prefix}as CPP=${cross_prefix}cpp"
  mkdir -p win64
  cd win64
    build_dependencies
    build_apps
  cd ..
fi

echo "searching for all local exe's (some may not have been built this round, NB)..."
for file in $(find_all_build_exes); do
  echo "built $file"
done
