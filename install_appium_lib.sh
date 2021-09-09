#!/bin/bash

cd /tmp
if [[ -e "ruby_lib" ]]; then
	echo "ruby_lib folder is found in /tmp directory"
	read -r -p "Delete the folder? (y/N): " response
	if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
	then
		rm -r ruby_lib
	else
		echo "ruby_lib folder must be deleted from the /tmp directory to be able to install appium_lib"
		exit
	fi
fi
if [[ -z $(which git) || -z $(which gem) || -z $(which rake) ]]; then
	echo "git, gem and rake must be present on the system"
else
	if [[ -n $(gem list | grep rubocop) ]]; then
		git clone https://github.com/EinarsNG/ruby_lib.git
		cd ruby_lib
		rake install
		cd ..
		rm -r ruby_lib
	else
		read -r -p "Rubocop not found. Would you like to install it? (y/N): " response
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
		then
			gem install rubocop
		else
			echo "Rubocop is required for this script for build appium_lib"
			exit
		fi
	fi
fi