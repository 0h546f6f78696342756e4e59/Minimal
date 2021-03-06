#!/bin/bash
cd $(dirname $0)

###############
## Variables ##
###############

unset HISTFILE
SSHPORT=""

#############################
## Configuration Functions ##
#############################

# Runs Through Configuration Functions
function configure_basic {
	# Configure Defaults
	configure_defaults

	# Remove Useless Gettys
	configure_getty

	# Ask If BASH History Should Be Disabled
	echo -n "Do you wish to disable BASH history? (Y/n): "
	read -e OPTION_HISTORY
	if [ "$OPTION_HISTORY" != "n" ]; then
		configure_history
	fi

	# Ask If SSH Port Should Be Changed
	echo -n "Do you wish to run SSH on different ports? (y/N): "
	read -e OPTION_SSHPORT
	if [ "$OPTION_SSHPORT" == "y" ]; then
		configure_sshport
	fi

	# Ask If SSH Logins Should Be Rate Limited
	echo -n "Do you wish to rate limit SSH? (y/N): "
	read -e OPTION_SSHRATE
	if [ "$OPTION_SSHRATE" == "y" ]; then
		configure_sshrate
	fi

	# Ask If Root SSH Should Be Disabled
	echo -n "Do you wish to disable root SSH logins? Keep enabled if you don't plan on making any users! (Y/n): "
	read -e OPTION_SSHROOT
	if [ "$OPTION_SSHROOT" != "n" ]; then
		configure_sshroot
	fi

	# Ask If Time Zone Should Be Set
	echo -n "Do you wish to set the timezone? (Y/n): "
	read -e OPTION_TZ
	if [ "$OPTION_TZ" != "n" ]; then
		configure_timezone
	fi

	# Ask If User Should Be Made
	echo -n "Do you wish to create a user account? (Y/n): "
	read -e OPTION_USER
	if [ "$OPTION_USER" != "n" ]; then
		configure_user
	fi

	# Reconfigure Dash
	dpkg-reconfigure dash

	# Clean Up
	configure_final
}

# Cleans Dotfiles
function configure_defaults {
	echo \>\> Configuring: Defaults
	# Remove Home Dotfiles
	rm -rf ~/.??*
	# Remove Skel Dotfiles
	rm -rf /etc/skel/.??*
	# Update Home Dotfiles
	cp -a -R settings/skel/.??* ~
	# Update Skel Dotfiles
	cp -a -R settings/skel/.??* /etc/skel
}

# Cleans Home
function configure_final {
	echo \>\> Configuring: Finalizing
	# Remove All Home Files
	rm -rf ~/*
	# Remove Skel SSH Directory
	rm -rf /etc/skel/.ssh
}

# Clean Getty
function configure_getty {
	echo \>\> Configuring: Gettys
	sed -e 's/\(^[2-6].*getty.*\)/#\1/' -i /etc/inittab
}

# Disables BASH History
function configure_history {
	echo \>\> Configuring: BASH History
	echo "unset HISTFILE" >> /etc/profile
}

# Changes SSH Port To User Specification
function configure_sshport {
	echo \>\> Configuring: Changing SSH Ports
	echo -n "Please enter an additional SSH Port: "
	read -e SSHPORT
	sed -i 's/#Port/Port '$SSHPORT'/g' /etc/ssh/sshd_config
	sed -i 's/DROPBEAR_EXTRA_ARGS="-w/DROPBEAR_EXTRA_ARGS="-w -p '$SSHPORT'/g' /etc/default/dropbear
}

# Enables SSH Login Rate Limiting
function configure_sshrate {
	echo \>\> Configuring: Rate Limiting SSH Logins
	# Enables SSH Login Rate Limiting
	iptables -N SSH_CHECK
	iptables -A INPUT -p tcp --dport 22 -m state --state NEW -j SSH_CHECK
	if [ "$SSHPORT" != "" ]; then
		iptables -A INPUT -p tcp --dport $SSHPORT -m state --state NEW -j SSH_CHECK
	fi
	iptables -A SSH_CHECK -m recent --set --name SSH
	iptables -A SSH_CHECK -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
	# Saves Limits
	iptables-save > /etc/firewall.conf
	echo '#!/bin/sh' > /etc/network/if-up.d/iptables
	echo "iptables-restore < /etc/firewall.conf" >> /etc/network/if-up.d/iptables
	chmod +x /etc/network/if-up.d/iptables
}

# Enables Root SSH Login
function configure_sshroot {
	echo \>\> Configuring: Enabling Root SSH Login
	sed -i 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
	sed -i 's/"-w/"/g' /etc/default/dropbear
	sed -i 's/" /"/g' /etc/default/dropbear
}

# Sets Time Zone
function configure_timezone {
	echo \>\> Configuring: Time Zone
	dpkg-reconfigure tzdata
}

# Adds User Account
function configure_user {
	echo \>\> Configuring: User Account
	echo -n "Please enter a user name: "
	read -e USERNAME
	useradd -m $USERNAME
	passwd $USERNAME
}

############################
## Installation Functions ##
############################

# Executes Install Functions
function install_basic {
	packages_update
	packages_purge
	packages_create
	packages_clean
	packages_purge
}

# Installs Lightweight Dropbear SSH Server & OpenSSH For SFTP Support
function install_dropbear {
	echo \>\> Configuring Dropbear
	# Installs Dropbear
	apt-get install dropbear
	# Updates Configuration Files
	cp settings/dropbear /etc/default/dropbear
	# Installs OpenSSH For SFTP Support
	install_ssh
	# Removes OpenSSH Daemon
	update-rc.d -f ssh remove
	# Cleans Package List
	packages_purge
}

# Installs Extra Packages Defined In List
function install_extra {
	# Loops Through Package List
	while read package; do
		# Installs Currently Selected Package
		apt-get -q -y install $package
	done < lists/extra
	# Cleans Cached Packages
	apt-get clean
}

# Installs OpenSSH And Sets Configuration
function install_ssh {
	echo \>\> Configuring SSH
	# Installs OpenSSH
	apt-get install openssh-server
	# Updates Configuration Files
	cp settings/sshd /etc/ssh/sshd_config
	cp settings/ssh /etc/ssh/ssh_config
	# Restarts OpenSSH Daemon
	/etc/init.d/ssh restart
	# Cleans Package List
	packages_purge
}

#######################
## Package Functions ##
#######################

# Uses DPKG To Remove Packages
function packages_clean {
	echo \>\> Cleaning Packages
	# Clear DPKG Package Selections
	dpkg --clear-selections
	# Set Package Selections
	dpkg --set-selections < lists/temp
	# Get Selections And Set To Purge
	dpkg --get-selections | sed -e 's/deinstall/purge/' > /tmp/dpkg
	# Set Package Selections
	dpkg --set-selections < /tmp/dpkg
	# Update DPKG
	apt-get dselect-upgrade
	# Upgrade Any Outdated Packages
	apt-get upgrade
}

# Creates Package List
function packages_create {
	echo \>\> Creating Package List
	# Copy Base Package List
	cp lists/base lists/temp
	# OpenVZ Check
	if [ -f /proc/user_beancounters ] || [ -d /proc/bc ]; then
		echo Detected OpenVZ!
	# Physical Hardware/Hardware Virtualisation
	else
		# Copy Base Package List
		cat lists/base-hw >> lists/temp
		# Detect x86
		if [ $(uname -m) == "i686" ]; then
			echo Detected i686!
			cat lists/kernel-i686 >> lists/temp
		fi
		# Detect x86_64
		if [ $(uname -m) == "x86_64" ]; then
			echo Detected x86_64!
			cat lists/kernel-x86_64 >> lists/temp
		fi
		# Detect XEN PV x86
		if [[ $(uname -r) == *xen* ]] && [ $(uname -m) == "i686" ]; then
			echo Detected XEN PV i686!
			cat lists/kernel-i686 >> lists/temp
			cat lists/kernel-xen-i686 >> lists/temp
		fi
		# Detect XEN PV x86_64
		if [[ $(uname -r) == *xen* ]] && [ $(uname -m) == "x86_64" ]; then
			echo Detected XEN PV x86_64!
			cat lists/kernel-x86_64 >> lists/temp
			cat lists/kernel-xen-x86_64 >> lists/temp
		fi
	fi
	# Sort Package List
	sort -o lists/temp lists/temp
}

# Purges APT Package Lists
function packages_purge {
	echo \>\> Cleaning Package States
	# Empty Package List Files
	echo -n > /var/lib/apt/extended_states
	# Cleans Cached Packages
	apt-get clean
}

# Updates Sources List & APT
function packages_update {
	echo \>\> Setting Up APT Sources
	# Copies Sources
	cp settings/sources /etc/apt/sources.list
	# Adds DotDeb Source Key
	wget http://www.dotdeb.org/dotdeb.gpg -qO - | apt-key add -
	# Updates Package Lists
	apt-get update
}

#################
## Init Script ##
#################

case "$1" in
	# Minimises System And Installs Dropbear
	dropbear)
		install_basic
		install_dropbear
	;;
	# Installs Extra Packages
	extra)
		install_extra
	;;
	# Configures Install
	configure)
		configure_basic
	;;
	# Minimises System And Installs OpenSSH
	ssh)
		install_basic
		install_ssh
	;;
	# Shows Help
	*)
		echo \>\> You must run this script with options. They are outlined below:
		echo For a minimal Dropbear based install: bash minimal.sh dropbear
		echo For a minimal OpenSSH based install: bash minimal.sh ssh
		echo To install extra packages defined in lists/extra: bash minimal.sh extra
		echo To set the clock, clean files and create a user: bash minimal.sh configure
	;;
esac
