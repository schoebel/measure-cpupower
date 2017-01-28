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
base_dir="${base_dir:-capture-cpupower-tmp}"
bench_dir="${bench_dir:-$base_dir/WordPress.git}"
create_copies="${create_copies:-0}" # check whether full WP copies can impact performance
pre_cmd="${pre_cmd:-if (( $create_copies )); then cd $bench_dir.\$instance; else cd $bench_dir; fi || exit \$?}"
cmd="${@:-i=0 && while (( i++ < 20 )); do (php index.php); done}"

# automatically derived
if (( create_copies )); then
    extra_name=copied_instances
else
    extra_name=common_instance
fi

mkdir -p "$base_dir"
if ! [[ -d $bench_dir ]]; then
    echo "Downloading WordPress"
    git clone "$git_url" "$bench_dir" || exit $?
fi
if ! [[ -f $bench_dir/wp-config.php ]]; then
    cp -a $bench_dir/wp-config-sample.php $bench_dir/wp-config.php || exit $?
fi
for host in $host_list; do
    remote "$host" "mkdir -p \"$base_dir\""
    rsync -av --exclude=".git" "$bench_dir" "root@$host:$base_dir/" || exit $?
    if (( create_copies )); then
	copy_cmd="for copyname in $(eval echo \"$bench_dir.{0..$max_para}\"); do rsync -a $bench_dir/ \$copyname/; done; sync"
	remote "$host" "$copy_cmd" &
    fi
done

wait
