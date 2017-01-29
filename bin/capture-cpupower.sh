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

# generic cmdline parameters
while [[ "$1" =~ ^-- ]]; do
    arg="$1"
    shift
    var="$(echo "$arg" | cut -d= -f1 | sed 's/^--//' | sed 's/-/_/g')"
    if [[ "$var" =~ = ]]; then
	val="$(echo "$arg" | cut -d= -f2)"
    else
	val=1
    fi
    eval "$var=$val"
done

# include generic infastructure
source "$(dirname "$0")/plugins/remote.sh" || exit $?

# general parameters
hardwaretype="${hardwaretype:-gamer_pc}" # result file naming
vmtype="${vmtype:-bare_metal}"           # result file naming
extra_name="${extra_name:-standard}"     # result file naming
host_list="${host_list:-box}" # used for round-robin load distribution
max_para="${max_para:-128}"   # typically a power of 2
max_time="${max_time:-60}"
# iteration-based method is only used when max_time == 0
max_factor="${max_factor:-6}"
max_iterations="${max_iterations:-$(( max_para * max_factor ))}"

# which command should be repeatedly executed?
plugin="${plugin:-wordpress}"
if [[ "$plugin" != "" ]]; then
    source "$(dirname "$0")/plugins/$plugin.sh" || exit $?
else
    plugin="direct"
    pre_cmd="${pre_cmd:-:}"
    cmd="${@:-i=0; while (( i++ < 100 )); do ls; done}"
fi

# further definitions
time_cmd="${time_cmd:-/usr/bin/time}"
time_format="${time_format:-%e:%U:%S:%M:%K:%c:%w:%I:%O:%x}"
time_columns="${time_columns:-$time_format}"
tmp_dir="/tmp/cpupower.$$"
rm -rf /tmp/cpupower.*

function run_single_benchmark
{
    local host="$1"
    local pre_cmd="$2"
    local cmd="$3"
    local para="$4"
    local instance="$5"

    cmd="$time_cmd --format=\"MEASURED:\$(hostname):\$(pwd):\$instance:\$para:\$round:$time_format\" bash -c \"$cmd\""

    if (( max_time > 0 )); then
        # time based benchmark repetitions
	cmd="instance=$instance; para=$para; round=0; $pre_cmd; start=\$(date +%s); while (( \$(date +%s) < start + $max_time )); do ( $cmd > /dev/null); done"
    else
        # iteration-based method
	local iterations="$(( max_iterations / para ))"
	cmd="instance=$instance; para=$para; round=0; $pre_cmd; while (( round++ < $iterations )); do ( $cmd > /dev/null); done"
    fi

    remote "$host" "$cmd"
}

function run_benchmark_parallel
{
    local para="$1"
    
    local -a host_array
    local host_count=0
    local host
    for host in $host_list; do
	host_array[$host_count]="$host"
	(( host_count++ ))
    done

    rm -rf $tmp_dir
    mkdir -p $tmp_dir

    local i=0
    while (( i++ < para )); do
	local index=$(( i % host_count ))
	host="${host_array[$index]}"
	#echo "$host $cmd"
	run_single_benchmark "$host" "$pre_cmd" "$cmd" "$para" "$i" \
	    2> "$tmp_dir/res.$i.txt" &
    done

    wait

    local out_name="benchmark-$plugin-$hardwaretype-$vmtype-$host_count-$extra_name-$para.csv"
    echo "Generating $out_name"
    {
	echo "HEADER:host:pwd:instance:parallelism:round:$time_columns"
	cat $tmp_dir/res.*.txt |\
	    grep "^MEASURED:"
    } > $out_name
    rm -rf $tmp_dir
}

function run_series
{
    local para=1
    local incr=1
    while (( para <= max_para )); do
	if (( max_time > 0 )); then
	    local txt="$max_time s"
	else
	    local txt="$max_iterations iterations"
	fi
	echo "---- para=$para BENCH $txt on $host_list"
	run_benchmark_parallel $para
	(( para += incr ))
	if (( !(para % (incr * 4)) )); then
	    (( incr *= 2 ));
	fi
    done
}

run_series
