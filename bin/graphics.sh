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

picturetype="${picturetype:-pdfcairo}"
pictureoptions="${pictureoptions:=fontscale 0.6 size 26cm, 18cm}"

col_round="\$6"
col_elapsed="\$7"
col_user="\$8"
col_system="\$9"

function get_class
{
    local name="$1"
    basename "$name" |\
	sed 's/^\(.*\)-[0-9]\+\.csv/\1/' |\
	sed 's/benchmark-//g'
}

function get_para
{
    local name="$1"
    basename "$name" | sed 's/^.*-\([0-9]\+\)\.csv/\1/'
}

function filter
{
    # ignore last line which may be disturbed by less parallelism
    grep -v "^HEADER" |\
	head --lines=-1
}

function plot_files
{
    local infiles="$1"
    local -A classes
    local -A files
    local plot=""
    local file
    for file in $infiles; do
	local class="$(get_class $file)"
	local para="$(get_para $file)"
	#echo "$para : $class"
	files[$file]="$class"
	classes[$class]="${classes[$class]} $file"
    done
    rm -f *.dat
    local class
    for class in ${!classes[*]}; do
	echo "------ CLASS $class"
	for file in ${classes[$class]}; do
	    #echo "  FILE $file" >> /dev/stderr
	    local para="$(get_para "$file")"
	    filter < $file |\
		awk -F":" "{ count++; sum += $col_elapsed; } END{ print $para, sum / count; }"
	done | sort -n > latency-$class.dat
	for file in ${classes[$class]}; do
	    #echo "  FILE $file" >> /dev/stderr
	    local para="$(get_para "$file")"
	    filter < $file |\
		awk -F":" "{ count++; sum += $col_elapsed; if ($col_round > streams) { streams = $col_round; } } END{ print $para, count * $para / sum; }"
	done | sort -n > throughput-$class.dat
	for file in ${classes[$class]}; do
	    #echo "  FILE $file" >> /dev/stderr
	    local para="$(get_para "$file")"
	    filter < $file |\
		awk -F":" "{ count++; sum += $col_user + $col_system; } END{ print $para, sum / count; }"
	done | sort -n > overhead-$class.dat
    done

    echo "------ PLOTTING latency"
    local plot=""
    for file in latency-*.dat; do
	[[ "$plot" != "" ]] &&  plot+=", "
	plot+="\"$file\" with lines"
    done
gnuplot <<EOF
set term $picturetype $pictureoptions;
set output "latency.pdf";
set title "Request Latency";
set xlabel "Number of Parallel Processes";
set ylabel "Time per Request [s]"
set logscale x;
set logscale y;
plot $plot;
EOF

    echo "------ PLOTTING throughput"
    local plot=""
    for file in throughput-*.dat; do
	[[ "$plot" != "" ]] &&  plot+=", "
	plot+="\"$file\" with lines"
    done
gnuplot <<EOF
set term $picturetype $pictureoptions;
set output "througput.pdf";
set title "Request Throughput";
set xlabel "Number of Parallel Processes";
set ylabel "Requests per Second"
set logscale x;
plot $plot;
EOF

    echo "------ PLOTTING overhead"
    local plot=""
    for file in overhead-*.dat; do
	[[ "$plot" != "" ]] &&  plot+=", "
	plot+="\"$file\" with lines"
    done
gnuplot <<EOF
set term $picturetype $pictureoptions;
set output "overhead.pdf";
set title "Overhead caused by CPU Caches and Kernel";
set xlabel "Number of Parallel Processes";
set ylabel "Average User+System Time"
set logscale x;
plot $plot;
EOF
}

if [[ "$1" != "" ]]; then
    params="$(ls "$@")"
else
    params="$(find . -type f -name "benchmark-*.csv" | grep -v "old\|ignore")"
fi
plot_files "$params"