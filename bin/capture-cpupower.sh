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
max_para="${max_para:-2048}"  # typically a power of 2
accuracy_x="${accuracy_x:-8}" # should _then_ also be a power of 2
max_time="${max_time:-60}"    # iterate bench until max runtime is exceeded
# iteration-based method is only used when max_time == 0
max_factor="${max_factor:-6}"
max_iterations="${max_iterations:-$(( max_para * max_factor ))}"

# Which command should be repeatedly executed?
# Plugins will usually set both $pre_cmd and $cmd and should be used for
# lab automation of larger projects.
# They can have their own sub-parameters.
# The generic $cmd provisioning from outside is intended for quick generic
# test setups on-the-fly, not for automating large test series.
plugin_list="${plugin_list:-wordpress}"
if [[ "$plugin_list" != "" ]]; then
    for plugin in $plugin_list; do
	source "$(dirname "$0")/plugins/$plugin.sh" || exit $?
    done
    plugin_txt="${plugin_txt:-$(echo "$plugin_list" | sed 's:^.*/::g' | sed 's/ \+/_/g')}"
else
    pre_cmd="${pre_cmd:-:}"
    cmd="${@:-i=0; while (( i++ < 100 )); do ls; done}"
    plugin_txt="${plugin_txt:-direct}"
    # show only short commands in the names (long ones will be obfuscating)
    if ! [[ "$cmd" =~ " " ]]; then
	plugin_txt+="_$cmd"
    fi
fi

# further definitions
time_cmd="${time_cmd:-/usr/bin/time}"
time_format="${time_format:-%e:%U:%S:%M:%K:%c:%w:%I:%O:%x}"
time_columns="${time_columns:-$time_format}"
tmp_dir="/tmp/cpupower.$$"
rm -rf /tmp/cpupower.*

function run_benchmarks
{
    local pre_cmd="$1"
    local main_cmd="$2"
    local para="$3"

    local -a host_array
    local host_count=0
    local host
    for host in $host_list; do
	host_array[$host_count]="$host"
	(( host_count++ ))
    done

    rm -rf $tmp_dir
    mkdir -p $tmp_dir

    main_cmd="$time_cmd --format=\"MEASURED:\$(hostname):\$(pwd):\$instance:\$para:\$round:$time_format\" bash -c \"$main_cmd\""

    if (( max_time > 0 )); then
        # time based benchmark repetitions
	local start="$(date +%s)"
	main_cmd="start=$start; para=$para; round=0; $pre_cmd; while (( \$(date +%s) < start + 10 )); do usleep 1000 || sleep 1; done; start=\$(date +%s); while (( \$(date +%s) < start + $max_time )); do (( round++ )); ($main_cmd) > /dev/null; done"
    else
        # iteration-based method
	local iterations="$(( max_iterations / para ))"
	main_cmd="para=$para; round=0; $pre_cmd; while (( round++ < $iterations )); do ($main_cmd) > /dev/null; done"
    fi

    local -A cmd_arr
    local i=0
    while (( i++ < para )); do
	local index=$(( i % host_count ))
	host="${host_array[$index]}"
	#echo "$host $main_cmd"
	cmd_arr[$host]+=" $i"
    done

    for host in ${!cmd_arr[*]}; do
	remote "$host" "rm -f /tmp/cpupower.*; for instance in ${cmd_arr[$host]}; do ($main_cmd) 2> /tmp/cpupower.\$instance & done; wait; cat /tmp/cpupower.*" \
	    > "$tmp_dir/res.$host.txt" &
    done

    wait

    local out_name="benchmark-$plugin_txt-$hardwaretype-$vmtype-$host_count-$extra_name-$para.csv"
    echo "Generating $out_name"
    {
	echo "HEADER:host:pwd:instance:parallelism:round:$time_columns"
	cat $tmp_dir/res.*.txt |\
	    grep "^MEASURED:"
    } > $out_name
    rm -rf $tmp_dir
}

function run_benchmark_parallel
{
    local para="$1"

    run_benchmarks "$pre_cmd" "$cmd" "$para"
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
	if (( !(para % (incr * accuracy_x)) )); then
	    (( incr *= 2 ));
	fi
    done
}

run_series
