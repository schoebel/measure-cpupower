#!/bin/bash
#
# Copyright 2017 Thomas Schoebel-Theuer
# Programmed in my spare time on my private computers.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

# Developed during my spare time

git_url="${git_url:-https://github.com/WordPress/WordPress}"
bench_dir="${bench_dir:-WordPress.git}"
cmd="${@:-cd $bench_dir && i=0 && while (( i++ < 20 )); do (php index.php); done}"

if ! [[ -d $bench_dir ]]; then
    echo "Downloading WordPress"
    git clone "$git_url" "$bench_dir" || exit $?
fi
if ! [[ -f $bench_dir/wp-config.php ]]; then
    cp -a $bench_dir/wp-config-sample.php $bench_dir/wp-config.php || exit $?
fi
for host in $host_list; do
    rsync -av $bench_dir root@$host: || exit $?
done
