#!/bin/bash
#
#  Copyright (C) 2014-2018 Dennis Stampfer, Matthias Lutz, Alex Lotz
#
#        Servicerobotik Ulm
#        University of Applied Sciences
#        Prittwitzstr. 10
#        D-89075 Ulm
#        Germany
#
#  Redistribution and use in source and binary forms, with or without modification, 
#  are permitted provided that the following conditions are met:
#  
#  1. Redistributions of source code must retain the above copyright notice, 
#     this list of conditions and the following disclaimer.
#  
#  2. Redistributions in binary form must reproduce the above copyright notice, 
#     this list of conditions and the following disclaimer in the documentation 
#     and/or other materials provided with the distribution.
#  
#  3. Neither the name of the copyright holder nor the names of its contributors 
#     may be used to endorse or promote products derived from this software 
#     without specific prior written permission.
#  
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
#  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
#  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
#  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
#  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
#  OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
#  OF THE POSSIBILITY OF SUCH DAMAGE.
#
#
# Dennis Stampfer 10/2014
# updates+compiles the virtual machine image to new ACE/smartsoft and toolchain version
#
# Matthias Lutz 10/2014
# install ACE/SmartSoft and dependencies to a clean Ubuntu 12.04 LTS install
#
# Dennis Stampfer 13.11.2014
# Error handling, bugfixes, Ace instead of Ace Tao, added ssh to packages list
#
# Dennis Stampfer 13.11.2014
# Verbose download for large (toolchain) file.
#
# Matthias Lutz 14.01.2016
# update locations of robotino repos
#
# Dennis Stampfer 15.1.2016
# Compatibility for raspberry-pi / arm architecture. More specific: Raspbian 8.0/jessie
#
# Matthias Lutz 00.12.2016
# Ununtu 16.04 as supported OS
#
# Dennis Stampfer 23.7.2018
# Adoption to v3-generation of SmartSoft World
#
# Dennis Stampfer, Alex Lotz 7.8.2018
# Update of Component Developer API way of installation
#
# Dennis Stampfer 9 2018
# Adoption to work on raspberry pi
#
# Dennis Stampfer 5.11.2018
# Fixing an issue with "source .profile" with custom prompts
#
# Dennis Stampfer 20.12.2018
# Temporarily deactivating toolchain installer since we are changing installation procedure
#
# Alex Lotz 23.10.2019
# Add check_sudo function and add latest toolchain installation commands
#
# Alex Lotz 12.12.2019
# Update Toolchain Installation to use version 3.12
#
# DO NOT ADD CODE ABOVE THIS LINE
# The following if is to test the update script.
if [ "$1" == "script-update-test" ]; then
	echo "ok"
	exit 0
fi
BCMD=$1 #fixes overwriting of prompt in .bashrc which we will source' later.
################################
# Insert code after here
################################

source ~/.profile

SCRIPT_DIR=`pwd`
SCRIPT_NAME=$0
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/MiRON-project/UtilityRepository/master/smartsoft-install-updatescript.sh"

TOOLCHAIN_NAME="SmartMDSD-Toolchain"
TOOLCHAIN_VERSION="3.12"
TOOLCHAIN_URL="https://github.com/Servicerobotics-Ulm/SmartMDSD-Toolchain/releases/download/v$TOOLCHAIN_VERSION/SmartMDSD-Toolchain-v$TOOLCHAIN_VERSION.tar.gz"
TOOLCHAIN_LAUNCHER="$TOOLCHAIN_NAME.desktop"

function abort() {
	echo 100 > /tmp/install-msg.log
	echo -e "\n\n### Aborted.\nYou can find a logfile in your current working directory:\n"
	pwd
	kill `cat /tmp/smartsoft-install-update.pid`
}

function askabort() {
	if zenity --width=400 --question --text="An error occurred (see log file). Abort update script?\n"; then
		abort
	fi
}

function progressbarinfo() {
	echo "# $1" > /tmp/install-msg.log
	echo -e "\n\n"
	echo "# $1"
	echo -e "\n\n"
}

# check if sudo is allowed and if necessary ask for password
function check_sudo() {
  local prompt

  # check for sudo rights without prompt
  prompt=$(sudo -nv 2>&1)
  if [ $? -eq 0 ]; then
    echo "has_sudo"
  elif echo $prompt | grep -q '^sudo:'; then
    PASSWD=$(zenity --title "sudo password" --password) || exit 1
    echo -e "$PASSWD\n" | sudo -Sv
    if [ $? -eq 0 ]; then
      echo "has_sudo"
    else
      abort
    fi
  else
    abort
  fi
}

function system_upgrade() {
	check_sudo
	sleep 2
	sudo apt -y update  || askabort
	sudo apt -y upgrade || askabort
	sudo apt -y autoremove || askabort
}

function create_remote_miron() {
	if [ ! -d .git/refs/remotes/miron ]; then
		git remote add miron $1 || askabort
	fi
	git remote update
}

function switch_master_branch() {
	if [ ! -n "$(git branch --list master)" ]; then
		git checkout -b master --track $1/$2 
	else
		git reset --hard $1/$2
		git branch master -u $1/$2
	fi	
}

function clone_repos() {
	if [ ! -d $1 ]; then
		git clone -o $1 --recurse-submodules $2 --progress 2>&1
	fi
}


if `grep --ignore-case precise /etc/os-release > /dev/null`; then 
	OS_PRECISE=true
fi

if `grep --ignore-case raspbian /etc/os-release > /dev/null`; then 
	OS_RASPBIAN=true
fi

if `grep --ignore-case xenial /etc/os-release > /dev/null`; then 
	OS_XENIAL=true
fi

if `grep --ignore-case bionic /etc/os-release > /dev/null`; then 
	OS_BIONIC=true
fi

if [ ! -x "$(command -v xterm)" ]; then
	check_sudo
	apt -y install xterm
fi

if [ ! -x "$(command -v zenity)" ]; then
	check_sudo
	apt -y install zenity
fi

case "$BCMD" in

###############################################################################
# MENU
###############################################################################
menu)
	if [ "$OS_RASPBIAN" = true ]; then 
		zenity --info  --width=400  --text="Raspberry Pi was detected. Performing specific instructions for raspberry pi."
	fi

	if [[ "$OS_XENIAL" = false ]] && [[ "$OS_BIONIC" = false ]]; then 
		zenity --info  --width=400 --text="Ubuntu 16.04 (Xenial) and Ubuntu 18.04 (Bionic) were not detected."
	fi

	ACTION=$(zenity \
		--title "SmartSoft Install & MIRoN set up" \
		--text "This is the automatic installation script for the SmartSoft World (v3-generation).\nThe default selection will install the SmartMDSD Toolchain with a full ACE/SmartSoft development environment.\n\nPlease select update actions to perform:\n\n* uses sudo: enter your password to the terminal window that pops up next." \
		--list --checklist \
		--height=400 \
		--width=800 \
		--column="" --column=Action --column=Description \
		--hide-column=2 --print-column=2 --hide-header \
		--separator="|" \
		false menu-install "1) Install ACE/SmartSoft Development Environment" \
		false miron-dependencies "2) Install MIRoN Dependencies"  \
		false toolchain-update "3) Update/Install SmartMDSD Toolchain to latest version" \
		false roqme-depend "4) Install RoQME Dependencies: OpenSliceDDS, GTK 2 and MPC" \
		false repo-up-smartsoft "5) Update ACE/SmartSoft Development Environment (updates repositories)" \
		false build-smartsoft "6) Build/Compile ACE/SmartSoftm DomainModels and Components (You must Run Code-Generation before)" \
	) || exit 1

	CMD=""
	IFS='|';
	for A in $ACTION; do
		CMD="$CMD bash $SCRIPT_NAME $A || askabort;"
	done
	LOGFILE=`basename $0`.`date +"%Y%m%d%H%M"`.log
	xterm -title "Updating..." -hold -e "exec > >(tee $LOGFILE); exec 2>&1; echo '### Update script start'; date; echo 'Logfile: $LOGFILE'; $CMD echo;echo;echo '### Update script finished. Logfile: $LOGFILE';echo 100 > /tmp/install-msg.log;echo;echo;rm /tmp/smartsoft-install-update.pid; date" &
	echo $! > /tmp/smartsoft-install-update.pid

	progressbarinfo "Starting ..."
	tail -f /tmp/install-msg.log | zenity --progress --title="Installing ..." --auto-close --text="Starting ..." --pulsate --width=500 &

	exit 0
;;

###############################################################################
# MENU INSTALL
###############################################################################
menu-install)
	progressbarinfo "Launching installation menu for ACE/SmartSoft"

	zenity --question --height=400 --width=800 --text="<b>ATTENTION</b>\n The script is about to install ACE/SmartSoft and dependencies on this system.\n<b>Only use this function on a clean installation of Ubuntu 16.04 or Ubuntu 18.04.</b> Some of the following steps may not be execute twice without undoing them before.\n\nDo you want to proceed?" || abort 

	ACTION=$(zenity \
		--title "Install ACE/SmartSoft and dependencies on a clean system" \
		--text "About to install a development environment.\nPlease select update actions to perform:\n" \
		--list --checklist \
		--height=400 \
		--width=800 \
		--column="" --column=Action --column=Description \
		--hide-column=2 --print-column=2 --hide-header \
		--separator="|" \
		false package-install "1.1) Install General Dependencies for ACE/SmartSoft/Miron" \
		false ace-source-install "1.2) Install ACE from source" \
		false repo-co-smartsoft "1.3) Clone repositories and set environment variables" \
	) || abort


	IFS='|';
	for A in $ACTION; do
		bash $SCRIPT_NAME $A || askabort
	done
	echo
	echo
	echo '### Install script finished.'
	progressbarinfo "Finished"
	echo
	echo

	exit 0
;;

###############################################################################
package-install)
	# become root
	if [ "$(id -u)" != "0" ]; then
		sudo bash $SCRIPT_NAME $1
		exit 0
	fi

	progressbarinfo "Running package install ..."
	sleep 2
	system_upgrade

	progressbarinfo "Installing packages ..."
	
	# General packages:
	apt -y install ssh-askpass git flex bison htop tree cmake cmake-curses-gui \
 subversion sbcl doxygen meld expect wmctrl libopencv-dev libboost-all-dev \
 libftdi-dev libopencv-dev build-essential pkg-config freeglut3-dev \
 zlib1g-dev zlibc libusb-1.0-0-dev libdc1394-22-dev libavformat-dev \
 libswscale-dev lib3ds-dev libjpeg-dev libgtest-dev libeigen3-dev libglew-dev \
 vim vim-gnome libxml2-dev libxml++2.6-dev libmrpt-dev ssh sshfs xterm \
 libjansson-dev libqt5*-dev qtwayland5 || askabort

	# Installing Gtest
	cd /usr/src/gtest || askabort
	mkdir -p build && cd build || askabort
	cmake .. || askabort
	make install || askabort
	cd


	progressbarinfo "Installing OS-specific packages ..."

	# 12.04 packages
	if [ "$OS_PRECISE" = true ]; then
		apt -y install libwxgtk2.8-dev openjdk-6-jre libtbb-dev || askabort
	fi

	# Other packages to install - except for raspberry pi:
	if [ "$OS_RASPBIAN" = true ]; then 
		apt -y install libwxgtk2.8-dev || askabort
	fi

	# Xenial (16.04 Packages)
	if [ "$OS_XENIAL" = true ]; then
		apt -y install openjdk-8-jre libtbb-dev || askabort
	fi

	# Bionic (18.04 Packages)
	if [ "$OS_BIONIC" = true ]; then
		apt -y install openjdk-8-jre openjdk-8-jdk || askabort
		apt -y install openjdk-11-jre openjdk-11-jdk libtbb-dev || askabort
	fi

	exit 0
;;

###############################################################################
ace-source-install)
	# become root
	if [ "$(id -u)" != "0" ]; then
		sudo bash $SCRIPT_NAME $1
		exit 0
	fi

	progressbarinfo "Running ACE source install (will take some time)"
	
	sleep 2
	wget -nv https://raw.githubusercontent.com/MiRON-project/AceSmartSoftFramework/master/INSTALL-ACE-6.5.8.sh -O /tmp/INSTALL-ACE-6.5.8.sh || askabort
	chmod +x /tmp/INSTALL-ACE-6.5.8.sh || askabort
	/tmp/INSTALL-ACE-6.5.8.sh /opt || askabort

	echo "/opt/ACE_wrappers/lib" > /etc/ld.so.conf.d/ace.conf || askabort
	ldconfig || askabort
	exit 0
;;

###############################################################################
roqme-depend)
	# become root
	if [ "$(id -u)" != "0" ]; then
		sudo bash $SCRIPT_NAME $1
		exit 0
	fi

	progressbarinfo "Running OpenSliceDDS/MPC (will take some time)"
	sleep 2

	# OpenSlice DDS
	wget -nv https://github.com/ADLINK-IST/opensplice/releases/download/OSPL_V6_9_190403OSS_RELEASE/PXXX-VortexOpenSplice-6.9.190403OSS-HDE-x86_64.linux-gcc7-glibc2.27-installer.tar.gz -O /tmp/OSPL_V6_9_190403OSS_RELEASE.tar.gz || askabort
	mkdir -p ~/SOFTWARE/smartsoft/OpenSpliceDDS || askabort
	tar -C ~/SOFTWARE/smartsoft/OpenSpliceDDS -zxvf /tmp/OSPL_V6_9_190403OSS_RELEASE.tar.gz || askabort
	sed -i '18iOSPL_HOME=$HOME/SOFTWARE/smartsoft/OpenSpliceDDS/HDE/x86_64.linux' ~/SOFTWARE/smartsoft/OpenSpliceDDS/HDE/x86_64.linux/release.com || askabort
	sed -i '1i#RoQME OpenSpliceDDS' ~/SOFTWARE/smartsoft/OpenSpliceDDS/HDE/x86_64.linux/release.com || askabort
	cat ~/SOFTWARE/smartsoft/OpenSpliceDDS/HDE/x86_64.linux/release.com >> ~/.profile || askabort
	source ~/.profile || askabort
	make -C $OSPL_HOME/custom_lib -f Makefile.Build_DCPS_ISO_Cpp2_Lib 
	
	# MPC
	mkdir -p ~/SOFTWARE/smartsoft/MPC || askabort
	git clone https://github.com/DOCGroup/MPC ~/SOFTWARE/smartsoft/MPC || askabort
	echo "# MPC" >> ~/.profile
	echo "export MPC_ROOT=\$HOME/SOFTWARE/smartsoft/MPC" >> ~/.profile
	source ~/.profile
	sed -i '7i--launcher.GTK_version' ~/SOFTWARE/SmartMDSD-Toolchain-v3.12/eclipse.ini || askabort
	sed -i '8i2' ~/SOFTWARE/SmartMDSD-Toolchain-v3.12/eclipse.ini || askabort

	# RoQME
	wget -nv https://github.com/roqme/robmosys-roqme-itp/raw/master/downloads/RoQME-Eclipse-Tools-v1.0_201904030901.zip -O /tmp/roqme.zip || askabort
	mkdir -p ~/SOFTWARE/smartsoft/RoQME || askabort
	unzip /tmp/roqme.zip -d ~/SOFTWARE/smartsoft/RoQME || askabort
	echo "export ROQME_ROOT=\$HOME/SOFTWARE/smartsoft/repos/ComponentRepository/MIRON-Components/QoSMetricProvider/roqme-dds/cpp" >> ~/.profile
	echo "export LD_LIBRARY_PATH=\$ROQME_ROOT/roqmeDDS/lib:\$LD_LIBRARY_PATH" >> ~/.profile
	echo "export CPATH=\$ROQME_ROOT/roqmeDDS/include:\$ROQME_ROOT/roqmeDDS/idl:\$CPATH" >> ~/.profile
	exit 0
;;

###############################################################################


###############################################################################
# Clone Servicerobotics-Ulm repositories from MIRON Organization
repo-co-smartsoft)

	progressbarinfo "Cloning Servicerobotics-Ulm repositories from MIRON or Servicerobotics-Ulm Organizations"

	sleep 2

	mkdir -p ~/SOFTWARE/smartsoft-ace-mdsd-v3/repos || askabort
	ln -sfn ~/SOFTWARE/smartsoft-ace-mdsd-v3 ~/SOFTWARE/smartsoft || askabort
	mkdir -p ~/SOFTWARE/smartsoft-ace-mdsd-v3/lib || askabort

	echo "export ACE_ROOT=/opt/ACE_wrappers" >> ~/.profile
	echo "export SMART_ROOT_ACE=\$HOME/SOFTWARE/smartsoft" >> ~/.profile
	echo "export SMART_PACKAGE_PATH=\$SMART_ROOT_ACE/repos" >> ~/.profile
	echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$SMART_ROOT_ACE/lib" >> ~/.bashrc

	source ~/.profile 

	cd ~/SOFTWARE/smartsoft-ace-mdsd-v3/repos || askabort

	progressbarinfo "Cloning repositories SmartSoftComponentDeveloperAPIcpp.git"
	clone_repos SmartSoftComponentDeveloperAPIcpp https://github.com/Servicerobotics-Ulm/SmartSoftComponentDeveloperAPIcpp.git || askabort
	
	progressbarinfo "Cloning repositories AceSmartSoftFramework.git"
	clone_repos AceSmartSoftFramework "https://github.com/Servicerobotics-Ulm/AceSmartSoftFramework.git" || askabort
	
	progressbarinfo "Cloning repositories UtilityRepository.git"
	clone_repos UtilityRepository "https://github.com/Servicerobotics-Ulm/UtilityRepository.git" || askabort
	
	progressbarinfo "Cloning repositories DataRepository.git"
	clone_repos DataRepository "https://github.com/MiRON-project/DataRepository.git" || askabort
	
	progressbarinfo "Cloning repositories DomainModelsRepositories.git"
	clone_repos DomainModelsRepositories https://github.com/Servicerobotics-Ulm/DomainModelsRepositories.git || askabort
	
	progressbarinfo "Cloning repositories ComponentRepository.git"
	clone_repos ComponentRepository https://github.com/Servicerobotics-Ulm/ComponentRepository.git || askabort
	
	progressbarinfo "Cloning repositories SystemRepository.git"
	clone_repos SystemRepository https://github.com/Servicerobotics-Ulm/SystemRepository.git || askabort

	progressbarinfo "Cloning repositories BehaviorRepository.git"
	clone_repos BehaviorRepository https://github.com/MiRON-project/BehaviorRepository.git || askabort

	zenity --info --width=400 --text="Environment settings in .profile have been changed. Execute 'source ~/.profile'"  --height=100

	exit 0
;;

###############################################################################
miron-dependencies)
	progressbarinfo "Launching installation menu for Miron Dependencies"

	zenity --question --height=100 --width=400 --text="The script is about to install Miron dependencies on this system.\n If you run this menu twice, you may need to fix the environment variables in ~/.profile.\n\nDo you want to proceed?" || abort 

	ACTION=$(zenity \
		--title "Install Miron Dependencies" \
		--text "Please select the programs you want to install (you should select only the programs that are not installed yet):\n" \
		--list --checklist \
		--height=200 \
		--width=400 \
		--column="" --column=Action --column=Description \
		--hide-column=2 --print-column=2 --hide-header \
		--separator="|" \
		false webots-install "2.1) Webots Simulator" \
		false mrpt-install "2.2) MRPT SLAM Library" \
		false ompl-install "2.3) OMPL - The Open Motion Planning Library " \
	) || abort


	IFS='|';
	for A in $ACTION; do
		bash $SCRIPT_NAME $A || askabort
	done
	echo
	echo
	echo '### Install script finished.'
	progressbarinfo "Finished"
	echo
	echo

	exit 0
;;

###############################################################################
webots-install)
	
	# Clone Dependencies
	mkdir -p $HOME/dev && cd $HOME/dev || askabort
	
	progressbarinfo "Clonning Webots Simulator"
	WEBOTS_EXEC="$HOME/dev/webots/webots"
	WEBOTS_DIR="$HOME/dev/webots/"
	if [[ ! -x "$(command -v webots)" ]]; then 
		if [[ ! -f "${WEBOTS_EXEC}" ]]; then 
			if [[ ! -d "${WEBOTS_DIR}" ]]; then
				clone_repos webots https://github.com/MiRON-project/webots.git || askabort
			else
				echo "You have webots folder in $HOME/dev/. And it is not properly installed. Remove it and run the script again."
				echo "Aborting..."
				sleep 5
				abort
			fi
		else
			echo "--found Webots. Just make sure to export WEBOTS_HOME variable properly in the ~/.profile file."	
			echo "Instructions in https://github.com/MiRON-project/DataRepository"
		fi
	else
		echo "--found Webots. Just make sure to export WEBOTS_HOME variable properly in the ~/.profile file."
		echo "Instructions in https://github.com/MiRON-project/DataRepository"
	fi

	progressbarinfo "Building Webots Simulator"
	if [ ! -x "$(command -v webots)" ] && [ ! -f "$WEBOTS_EXEC" ]; then
		check_sudo
		sudo apt -y install git g++ cmake execstack libusb-dev swig \
python2.7-dev libglu1-mesa-dev libglib2.0-dev libfreeimage-dev \
libfreetype6-dev libxml2-dev libzzip-0-13 libboost-dev libavcodec-extra \
libgd-dev libssh-gcrypt-dev libzip-dev python-pip libreadline-dev \
libassimp-dev pbzip2 libpci-dev || askabort
		sudo apt -y install libssl-dev ffmpeg python3.6-dev \
python3.7-dev || askabort
		cd $HOME/dev || askabort
		cd webots && make || askabort
		echo "export WEBOTS_HOME=\$HOME/dev/webots" >> ~/.profile
	fi

	zenity --info --width=400 --text="Environment settings in .profile have been changed. Execute 'source ~/.profile'"  --height=100
	exit 0
;;

###############################################################################
mrpt-install)
	
	mkdir -p $HOME/dev && cd $HOME/dev || askabort
	MRPT_PATH="$HOME/dev/mrpt/"
	if [ ! -d "${MRPT_PATH}" ]; then
		clone_repos mrpt https://github.com/MiRON-project/mrpt.git || askabort
	else
		echo "You have mrpt folder in $HOME/dev/. If you do not installed it properly, remove it and run the script again."
	fi
	
	progressbarinfo "Building MRPT"
	check_sudo
	sudo apt -y install build-essential pkg-config cmake \
	libwxgtk3.0-dev libwxgtk3.0-gtk3-dev libopencv-dev libeigen3-dev libgtest-dev \
	libftdi-dev freeglut3-dev zlib1g-dev libusb-1.0-0-dev libudev-dev libfreenect-dev \
	libdc1394-22-dev libavformat-dev libswscale-dev libassimp-dev libjpeg-dev \
	libsuitesparse-dev libpcap-dev liboctomap-dev libglfw3-dev || askabort
	mkdir -p $MRPT_PATH/build
	cd $MRPT_PATH/build 
	cmake .. || ( rm -rf $MRPT_PATH/build && askabort )
	make || (rm -rf $MRPT_PATH/build && askabort)
	ln -s $HOME/dev/mrpt/build/lib ~/SOFTWARE/smartsoft/lib || askabort
	mv ~/SOFTWARE/smartsoft/lib/lib ~/SOFTWARE/smartsoft/lib/mrpt || askabort
	echo "export MRPT_DIR=\$HOME/dev/mrpt/build" >> ~/.profile

	zenity --info --width=400 --text="Environment settings in .profile have been changed. Execute 'source ~/.profile'"  --height=100
	exit 0
;;

###############################################################################
ompl-install)

	mkdir -p $HOME/dev && cd $HOME/dev || askabort
	OMPL_PATH="$HOME/dev/ompl/"
	if [ ! -d "${OMPL_PATH}" ]; then
		mkdir -p ompl && cd ompl || askabort
		wget https://ompl.kavrakilab.org/install-ompl-ubuntu.sh
	else
		echo "You have ompl folder in $HOME/dev/. If you do not installed it properly, remove it and run the script again."
	fi

	progressbarinfo "Building OMPL"
	check_sudo
	chmod u+x install-ompl-ubuntu.sh
	./install-ompl-ubuntu.sh
	echo "export OMPL_BUILD=\$HOME/dev/ompl/ompl-1.5.0/build/Release/build" >> ~/.profile

	zenity --info --width=400 --text="Environment settings in .profile have been changed. Execute 'source ~/.profile'"  --height=100
	exit 0
;;

###############################################################################
repo-up-smartsoft)
	echo -e "\n\n\n### Running MIRoN repositories update ...\n\n\n"
	progressbarinfo "About to update repositories ..."
	sleep 2

	if zenity --question --width=800 --text="The installation script is about to update the repositories.\nThis will <b>overwrite all your modifications</b> that you did to the repositories in \$SMART_ROOT_ACE/repos/.\n\nDo you want to proceed?\n\nIt is safe to do so in case you did not modify SmartMDSD Toolchain projects or don't need the modifications anymore.\nIf you choose not to update, please do a 'git pull' for the repositories yourself."; then
		echo -e "\n\n\n# Continuing with repo update.\n\n\n"
	else
		echo -e "\n\n\n# Not running repo update.\n\n\n"
		exit 0
	fi
	
	source ~/.profile

	progressbarinfo "Updating SmartSoftComponentDeveloperAPIcpp..."
	cd $SMART_ROOT_ACE/repos/SmartSoftComponentDeveloperAPIcpp || askabort
	git reset --hard HEAD
	git pull || askabort

	progressbarinfo "Updating AceSmartSoftFramework..."
	cd $SMART_ROOT_ACE/repos/AceSmartSoftFramework || askabort
	git reset --hard HEAD
	git pull || askabort

	progressbarinfo "Updating UtilityRepository..."
	cd $SMART_ROOT_ACE/repos/UtilityRepository || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/UtilityRepository.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	progressbarinfo "Updating DataRepository..."
	cd $SMART_ROOT_ACE/repos/DataRepository || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/DataRepository.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	progressbarinfo "Updating DomainModelsRepositories..."
	cd $SMART_ROOT_ACE/repos/DomainModelsRepositories || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/DomainModelsRepositories.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	progressbarinfo "Updating ComponentRepository..."
	cd $SMART_ROOT_ACE/repos/ComponentRepository || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/ComponentRepository.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	progressbarinfo "Updating SystemRepository..."
	cd $SMART_ROOT_ACE/repos/SystemRepository || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/SystemRepository.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	progressbarinfo "Updating BehaviorRepository..."
	cd $SMART_ROOT_ACE/repos/BehaviorRepository || askabort
	git reset --hard HEAD
	create_remote_miron "https://github.com/MiRON-project/BehaviorRepository.git" || askabort
	switch_master_branch "miron" "master"
	git pull || askabort
	git submodule update --init --recursive || askabort

	exit 0
;;

###############################################################################
build-smartsoft)
	echo -e "\n\n\n### Running Build ACE/SmartSoft, Utilities, DomainModels and Components...\n\n\n"
	sleep 2

	if zenity --question --width=800 --text="The installation script is about to build the repositories.\nThis <b>won't work</b> if you did not Run Code-Generator for each Package individually.\n\nDo you want to proceed, did you run Code-Generator in Smartsoft-Toolkit?\n\n."; then
		echo -e "\n\n\n# Continuing with repo build.\n\n\n"
	else
		echo -e "\n\n\n# Not running repo build.\n\n\n"
		exit 0
	fi

	source ~/.profile
	progressbarinfo "Running Build ACE/SmartSoft SmartSoftComponentDeveloperAPIcpp ..."
	cd $SMART_ROOT_ACE/repos/SmartSoftComponentDeveloperAPIcpp || askabort
	mkdir -p build
	cd build || askabort
	cmake ..
	make install || askabort

	progressbarinfo "Running Build ACE/SmartSoft Kernel ..."
	# warkaround for the case when the kernel is not built automatically as external dependency
	cd $SMART_ROOT_ACE/repos/AceSmartSoftFramework || askabort
	mkdir -p build
	cd build || askabort
	cmake ..
	make install || askabort

	progressbarinfo "Running Build Utilities"
	cd $SMART_ROOT_ACE/repos/UtilityRepository || askabort
	mkdir -p build
	cd build || askabort
	cmake ..
	make || askabort

	progressbarinfo "Running Build DomainModels"
	cd $SMART_ROOT_ACE/repos/DomainModelsRepositories || askabort
	mkdir -p build
	cd build || askabort
	cmake ..
	make || askabort

	# The roqmeDDS
	progressbarinfo "RoQME DDS"
	check_sudo
	update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java
	cd $SMART_ROOT_ACE/repos/ComponentRepository/MIRON-Components/QoSMetricProvider/roqme-dds/cpp/roqmeDDS || askabort
	chmod +777 gen_makefile.sh || askabort
	./gen_makefile.sh || askabort
	make || askabort

	progressbarinfo "Running Build Components"
	cd $SMART_ROOT_ACE/repos/ComponentRepository || askabort
	mkdir -p build
	cd build || askabort
	cmake ..
	make || askabort

	# Data Repo: MOOD2BE, Groot and ZMQBroker
	progressbarinfo "Running Data Components"
	
	progressbarinfo "Building MOOD2Be"
	MOOD2BE_HOME="$HOME/dev/MOOD2Be"
	if [ ! -d "$MOOD2BE_HOME" ]; then
		echo "You don't have MOOD2BE in dev/ folder. Thus you are running the latest script version"
	else
		echo "You have MOOD2Be folder in $HOME/dev/. This is not the latest script version. It will be removed from here and added to DataRepository"
		rm -rf MOOD2BE_HOME
		sed -i '/MOOD2BE_DIR/d' ~/.profile
	fi
	MOOD2BE_HOME="$SMART_ROOT_ACE/repos/DataRepository/MOOD2Be" 
	MOOD2BE_DIR=$MOOD2BE_HOME/build
	mkdir -p $MOOD2BE_DIR
	cd $MOOD2BE_DIR
	cmake .. || (rm -rf $MOOD2BE_DIR && askabort)
	make || (rm -rf $MOOD2BE_DIR && askabort)
	if grep -Fxq "# MOOD2BE" ~/.profile
	then
		:
	else
		echo >> ~/.profile 
		echo "# MOOD2BE" >> ~/.profile
		echo "export MOOD2BE_DIR=\$SMART_ROOT_ACE/repos/DataRepository/MOOD2Be/build/Executor" >> ~/.profile
	fi

	progressbarinfo "Building Groot"
	GROOT_HOME="$SMART_ROOT_ACE/repos/DataRepository/Groot" 
	GROOT_DIR=$GROOT_HOME/build
	mkdir -p $GROOT_DIR
	cd $GROOT_DIR
	source ~/.profile || askabort
	cmake .. || (rm -rf $GROOT_DIR && askabort)
	make || (rm -rf $GROOT_DIR && askabort)
	if grep -Fxq "# GROOT" ~/.profile
	then
		:
	else
		echo >> ~/.profile 
		echo "# GROOT" >> ~/.profile
		echo "export GROOT_DIR=\$SMART_ROOT_ACE/repos/DataRepository/Groot/build" >> ~/.profile
	fi
	
	progressbarinfo "Building ZMQServer"
	ZMQSERVER_HOME="$SMART_ROOT_ACE/repos/DataRepository/ZMQServer" 
	ZMQSERVER_DIR=$ZMQSERVER_HOME/build
	mkdir -p $ZMQSERVER_DIR || askabort
	cd $ZMQSERVER_DIR || askabort
	source ~/.profile || askabort
	cmake .. || (rm -rf $ZMQSERVER_DIR && askabort)
	make || (rm -rf $ZMQSERVER_DIR && askabort)
	if grep -Fxq "# ZMQSERVER" ~/.profile
	then
		:
	else
		echo >> ~/.profile 
		echo "# ZMQSERVER" >> ~/.profile
		echo "export ZMQSERVER_DIR=\$SMART_ROOT_ACE/repos/DataRepository/ZMQServer/build" >> ~/.profile
	fi

	exit 0
;;

###############################################################################
toolchain-update)
	progressbarinfo "Running toolchain installation ..."
	# check if OpenJDK 8 is installed (autoinstall it if needed)
	if [[ $(java -version 2>&1) == "openjdk version \"1.8"* ]] || [[ $(java -version 2>&1) == "openjdk version \"11."* ]]; then
		echo "-- found OpenJDK 1.8 or greater"
	else
		progressbarinfo "Installing dependency OpenJDK 8 ..."
		check_sudo
		sudo apt install -y openjdk-8-jre || askabort
	fi

	progressbarinfo "Downloading the SmartMDSD Toolchain archive from: $TOOLCHAIN_URL"
	cd $HOME/SOFTWARE
	wget -N $TOOLCHAIN_URL || askabort
	wget --progress=dot:mega --content-disposition $TOOLCHAIN_URL || askabort

	progressbarinfo "Extracting the SmartMDSD Toolchain archive $TOOLCHAIN_NAME-v$TOOLCHAIN_VERSION.tar.gz" 
	tar -xzf $TOOLCHAIN_NAME-v$TOOLCHAIN_VERSION.tar.gz || askabort

	# create a desktop launcher
	echo "#!/usr/bin/xdg-open" > /tmp/$TOOLCHAIN_LAUNCHER
	echo "[Desktop Entry]" >> /tmp/$TOOLCHAIN_LAUNCHER
	echo "Name=SmartMDSD Toolchain v$TOOLCHAIN_VERSION" >> /tmp/$TOOLCHAIN_LAUNCHER	
	echo "Version=$TOOLCHAIN_VERSION" >> /tmp/$TOOLCHAIN_LAUNCHER
	
	cd $TOOLCHAIN_NAME-v$TOOLCHAIN_VERSION
	echo "Exec=$PWD/eclipse" >> /tmp/$TOOLCHAIN_LAUNCHER

	cd plugins/org.smartmdsd.branding*
	cd icons
	echo "Icon=$PWD/logo64.png" >> /tmp/$TOOLCHAIN_LAUNCHER

	echo "Terminal=false" >> /tmp/$TOOLCHAIN_LAUNCHER
	echo "Type=Application" >> /tmp/$TOOLCHAIN_LAUNCHER
	echo "Categories=Development;" >> /tmp/$TOOLCHAIN_LAUNCHER

	cd /tmp
	chmod +x $TOOLCHAIN_LAUNCHER
	cp $TOOLCHAIN_LAUNCHER $HOME/.local/share/applications/
	cp $TOOLCHAIN_LAUNCHER $(xdg-user-dir DESKTOP)

	exit 0
;;	

###############################################################################
# Update the installation script
###############################################################################
script-update)
	progressbarinfo "Updating the script before starting it ..."
	T=`tempfile`
	echo "Tempfile: $T"
	
	wget "$SCRIPT_UPDATE_URL" -O $T

	if [ "$(file --mime-type -b $T)" != "text/x-shellscript" ]; then
		zenity --info --text="Error updating the script."
		echo -e "\n # This is not a shell script."
		exit
	fi
	echo -e "\n # File is a shell script."

	if [ "$(bash $T script-update-test)" != "ok" ]; then
		zenity --info --text="Error updating the script."
		echo -e "\n # bash $T script-update-test : returned not OK"
		exit
	fi
	echo -e "\n # Test OK"

	mv $T $SCRIPT_NAME

	zenity --info --width=400 --text="Update finished. Please restart the\ninstallation script (and choose not to update)."

	exit 0
;;

###############################################################################
# The usual entry point of this script. We use this to determine the
# default action. No extra code should go here.
###############################################################################
start)
	bash $SCRIPT_NAME menu
;;




###############################################################################
*)
	if zenity --question --height=100 --width=800 --text="This installation and update script has an updater included.\nDo you want to update this script before continuing?\n\nUpdate location:\n$SCRIPT_UPDATE_URL\n"; then
		bash $SCRIPT_NAME script-update
		exit 0
	else
		echo -e "\n\n\n# Not updating the script before running it.\n\n\n"
	fi

	bash $SCRIPT_NAME start
;;


esac


