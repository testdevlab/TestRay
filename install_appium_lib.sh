#!/bin/bash

cd /tmp
if [[ -e ruby_lib ]]; then
	rm -r ruby_lib
fi
git clone https://github.com/EinarsNG/ruby_lib.git
cd ruby_lib
rake install
cd ..
rm -r ruby_lib
