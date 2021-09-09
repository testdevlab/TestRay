#!/bin/bash

cd /tmp
if [[ -e ruby_lib ]]; then
	rm -r ruby_lib
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
		echo Install Rubocop first: gem install rubocop
	fi
fi