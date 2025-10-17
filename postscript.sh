#!/bin/bash
# Usage: ./job_report.sh <jobid>

JOBID=$1

#CHECK
export LC_NUMERIC=C

# --- Helper functions --- #

# Helper: Convert time string (D-HH:MM:SS) to total hours (supports optional days)
time_to_hours() {
    local t=$1 d=0 h=0 m=0 s=0
    [[ $t == *-* ]] && { d=${t%%-*}; t=${t#*-}; }
    IFS=':' read -r h m s <<< "$t"
    echo "scale=4; ($d*24)+$h+($m/60)+($s/3600)" | bc -l
}

# Helper: Format time string (D-HH:MM:SS) to human-readable format ---
format_time() {
    local t=$1
    local days=0 hours=0 mins=0 secs=0
    if [[ "$t" == *-* ]]; then
        days=${t%%-*}
        t=${t#*-}
    fi
    IFS=: read -r hours mins secs <<< "$t"
    if [[ -z $secs ]]; then
        secs=$mins; mins=$hours; hours=0
    fi
    local out=""
    (( days > 0 )) && out+="${days}d"
    (( hours > 0 )) && out+="${hours}h"
    (( mins > 0 )) && out+="${mins}m"
    (( secs > 0 )) && out+="${secs}s"
    [[ -z $out ]] && out="0s"
    echo "$out"
}

# Helper: Convert H:MM:SS or M:SS(.ms) or single seconds -> seconds (supports fractional seconds)
time_str_to_secs() {
    local t="$1"
    t=$(echo "$t" | tr ',' '.' | tr -d '[:space:]')
    IFS=':' read -r a b c <<< "$t"
    if [ -z "$b" ]; then
        # plain seconds
        awk -v x="$a" 'BEGIN { printf "%.3f", x }'
    elif [ -z "$c" ]; then
        # MM:SS(.ms)
        awk -F: '{ printf "%.3f", ($1*60) + $2 }' <<< "$t"
    else
        # HH:MM:SS(.ms)
        awk -F: '{ printf "%.3f", ($1*3600) + ($2*60) + $3 }' <<< "$t"
    fi
}

# Helper: Convert memory string to GB
convert_to_gb() {
    local mem_str="$1"
    local default_unit="${2:-gb}"   # optional default unit (default: GB)

    # Extract numeric value and unit (handles cases like 1000Kc, 10.5G, etc.)
    local mem_value mem_unit
    mem_value=$(echo "$mem_str" | grep -oE '^[0-9]+(\.[0-9]+)?' | head -1)
    mem_unit=$(echo "$mem_str" | sed 's/^[0-9.]*//; s/[cn]$//' | tr '[:upper:]' '[:lower:]')

    # Default to provided default unit if empty
    [[ -z "$mem_unit" ]] && mem_unit="$default_unit"

    # Convert to GB
    case "$mem_unit" in
        k|kb)
            echo "$(echo "scale=6; $mem_value / 1024 / 1024" | bc -l)"
            ;;
        m|mb)
            echo "$(echo "scale=6; $mem_value / 1024" | bc -l)"
            ;;
        g|gb)
            printf "%.6f" "$mem_value"
            ;;
        t|tb)
            echo "$(echo "scale=6; $mem_value * 1024" | bc -l)"
            ;;
        *)
            # Fallback - assume GB
            echo "$mem_value"
            echo "Warning: Unknown memory unit '$mem_unit', assuming GB" >&2
            ;;
    esac
}

# Helper: Format memory display with appropriate units
format_memory() {
    local mem_gb=$1
    if (( $(echo "$mem_gb < 0.99" | bc -l) )); then
        # Less than 0.01 GB, show in MB
        mem_mb=$(echo "scale=4; $mem_gb * 1024" | bc)
        echo "${mem_mb}MB"
    else
        # 1 GB or more, show in GB with 0 decimal places
        echo "$(printf "%.0f" $mem_gb)GB"
    fi
}

# Helper: extract TRES value (e.g. gres/gpu=2) from a TRES string
get_tres_val() { echo "$1" | grep -oP "$2" | head -1 || echo "0"; }

# --- Job data --- #
# Fetch job data from sacct
FIELDS="JobID,Account,State,ExitCode,Partition,ReqCPUS,AllocCPUS,TotalCPU,ReqMem,ReqTRES,AllocTRES,Timelimit,Elapsed,NNodes,NodeList,MaxRSS,CPUtime,CPUTimeRAW"

JOB_DATA=$(sacct -n -j "$JOBID" --format="$FIELDS" -P)

# Check if job ID was found
if [ -z "$JOB_DATA" ]; then
    echo "Error: Job ${JOBID} not found."
    exit 1
fi

# Read job data lines into an array
IFS=$'\n' read -rd '' -a LINES <<< "$JOB_DATA"

# Read line 1 from sacct output: provides overall job info
IFS='|' read -r jobid account state exitcode partition reqcpus alloccpus totalcpu reqmem reqtres alloctres timelimit elapsed nnodes nodelist maxrss cputime cputimeraw <<< "${LINES[0]}"

# Read line 2 from sacct output: batch step info
if [[ ${#LINES[@]} -gt 1 && -n "${LINES[1]}" ]]; then
    IFS='|' read -r jobid_batch account_batch state_batch exitcode_batch partition_batch reqcpus_batch alloccpus_batch totalcpu_batch reqmem_batch reqtres_batch alloctres_batch timelimit_batch elapsed_batch nnodes_batch nodelist_batch maxrss_batch cputime_batch cputimeraw_batch <<< "${LINES[1]}"
fi

# Determine number of GCDs requested 
ngpus_alloc=$(get_tres_val "$alloctres" 'gres/gpu=\K[0-9]+')

# Defensive check for number of nodes requested
if [ -z "$nnodes" ]; then
    echo "Warning: nnodes is empty, defaulting to 1. Please check upstream job data." >&2
    nnodes=1
fi

# Clean exit code
exitcode=${exitcode%%:*}

# --- CPU efficiency (common to all partitions) --- #
# Convert elapsed and timelimit to hours
elapsed_hours=$(time_to_hours "$elapsed")
walltime_hours=$(time_to_hours "$timelimit")

# elapsed seconds from elapsed_hours
elapsed_secs=$(echo "$elapsed_hours * 3600" | bc -l)

# Convert sacct TotalCPU (e.g. "00:40:58" or "40:57.651") to seconds
totalcpu_secs=$(time_str_to_secs "$totalcpu")

# Calculate CPU efficiency
# Defensive fallbacks if something missing
if [ -z "$totalcpu_secs" ] || [ -z "$elapsed_secs" ] || [ -z "$alloccpus" ]; then
    cpu_efficiency="0.00"
else
    # Use TotalCPU as numerator (what seff calls "CPU Utilized")
    # Denominator is AllocCPUS * Elapsed_seconds (core-walltime)
    # multiply by 100 for percentage
    # prevent division by zero
    if (( $(echo "$alloccpus > 0 && $elapsed_secs > 0" | bc -l) )); then
        cpu_efficiency=$(echo "scale=3; ($totalcpu_secs / ($alloccpus * $elapsed_secs)) * 100.0" | bc -l)
    else
        cpu_efficiency="0.00"
    fi
fi
# -------------------------------- #

# --- Memory usage and efficiency --- #
# Collect maximum memory across ALL job steps
max_memory_all=$(sacct -j "$JOBID" --format=MaxRSS -n -P | grep -v "^$" | sort -h | tail -1)

# Requested memory (reqmem)
mem_requested_gb=$(convert_to_gb "$reqmem" "gb")

# Used memory (MaxRSS)
if [ -n "$max_memory_all" ]; then
    mem_used_gb=$(convert_to_gb "$max_memory_all" "kb")   # MaxRSS often defaults to KB
else
    mem_used_gb=0
fi

# Calculate memory efficiency as percentage
memory_efficiency=$(awk -v used="$mem_used_gb" -v req="$mem_requested_gb" 'BEGIN { if (req>0) printf "%.2f", (used/req)*100; else print "N/A" }')

# -------------------------------- #

# --- Service Unit Calculation --- #
# Detect partition type and set charge rates and node resources
case "$partition" in
    *gpu*)
        partition_type="gpu"
        charge_rate=512
        node_gpus=8
        ;;
    *highmem*)
        partition_type="highmem"
        charge_rate=128
        node_mem_gb=1011
        node_cores=128
        ;;
    *copy*)
        partition_type="copy"
        charge_rate=128
        node_mem_gb=235
        node_cores=64
        ;;    
    *)
        partition_type="cpu"
        charge_rate=128
        node_mem_gb=235
        node_cores=128
        ;;
esac

# Calculate service units (SUs) based on partition type
if [[ "$partition_type" == "gpu" ]]; then
    gpu_proportion=$(awk -v g="$ngpus_alloc" -v n="$node_gpus" 'BEGIN { if (n>0) printf "%.6f", g/n; else print 0 }')
    service_units=$(awk -v rate="$charge_rate" -v prop="$gpu_proportion" -v n="$nnodes" -v hrs="$elapsed_hours" \
        'BEGIN { printf "%.4f", rate * prop * n * hrs }')
else

# Calculate core and mem proportions, determine which is higher to use for SU calculation
    cores_proportion=$(awk -v a="$alloccpus" -v n="$node_cores" 'BEGIN { printf "%.6f", a/n }')
    mem_proportion=$(awk -v u="$mem_requested_gb" -v n="$node_mem_gb" 'BEGIN { p=u/n; if (p>1) p=1; printf "%.6f", p }')
    max_proportion=$(awk -v c="$cores_proportion" -v m="$mem_proportion" 'BEGIN { if (c>m) printf "%.6f", c; else printf "%.6f", m }')

    # --- SU calculation ---
    service_units=$(awk -v rate="$charge_rate" -v maxp="$max_proportion" -v n="$nnodes" -v hrs="$elapsed_hours" \
        'BEGIN { printf "%.4f", rate * maxp * n * hrs }')
fi
#######
format_elapsed() {
    local t="$1"
    IFS=':' read -r h m s <<< "$t"

    # If it's missing seconds (e.g., "03:11"), treat it as mm:ss
    if [[ -z "$s" ]]; then
        s="$m"
        m="$h"
        h="00"
    fi

    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

# Walltime efficiency check
walltime_efficiency=$(awk -v e="$elapsed_hours" -v w="$walltime_hours" 'BEGIN { if (w>0) printf "%.2f", (e/w)*100; else print "0" }')

# Ensure cpu_efficiency is formatted with 1 or 2 decimals
cpu_eff_fmt=$(printf "%.2f%%" "$cpu_efficiency")

# --- Report ---
current_date=$(date '+%Y-%m-%d %H:%M:%S')
echo "======================================================================================"
printf "                  Resource Usage on %s:\n" "$current_date"
printf "   Job Id:             %-23s Project: %s\n" "$jobid" "$account"
printf "   Partition:          %s\n" "$partition"
printf "   Exit Status:        %-23s Job State: %s\n" "$exitcode" "$state"
printf "   Service Units:      %.2f\n" "$service_units"
printf "   Nodes Requested:    %s\n" "$nnodes"
printf "   NCPUs Requested:    %-23s NCPUs Allocated: %s\n" "$reqcpus" "$alloccpus"
printf "   CPU Time Available: %-23s CPU Time Used: %s\n" "$cputime" "$(format_elapsed ${totalcpu%%.*})"
printf "   Memory Requested:   %-23s Memory Used: %s\n" "$(format_memory $mem_requested_gb)" "$(format_memory $mem_used_gb)"
printf "   Walltime Requested: %-23s Walltime Used: %s\n" "$timelimit" "$elapsed"
printf "   Walltime Efficiency:%s%%\n" "$walltime_efficiency"
printf "   CPU Efficiency:     %-23s Memory Efficiency: %s%%\n" "$cpu_eff_fmt" "$memory_efficiency"
if [[ "$partition_type" == "gpu" ]]; then
    printf "   GCDs Requested: %s\n" "$ngpus_alloc"
else 
    printf "   GCDs Requested: %-23s\n" "0"
fi
# --- Efficiency warnings and recommendations ---  #
echo "-------------------------------------------------------------------------------------"
echo "   Efficiency Analysis & Recommendations:"
echo ""

# Exit status check
if [ "$exitcode" != "0" ]; then
    echo "   ⚠ JOB FAILED (Exit code: $exitcode)"
    case "$exitcode" in
        1)   echo "     General error - check job logs" ;;
        125) echo "     Job exceeded memory limit" ;;
        126) echo "     Command cannot execute" ;;
        127) echo "     Command not found" ;;
        137) echo "     Job killed (SIGKILL) - possibly out of memory" ;;
        139) echo "     Segmentation fault" ;;
        140) echo "     Job exceeded walltime limit" ;;
        *)   echo "     Check job logs for details" ;;
    esac
fi

# Memory efficiency check
if [ -n "$memory_efficiency" ] && [ "$memory_efficiency" != "N/A" ]; then
    if (( $(echo "$memory_efficiency < 10" | bc -l) )); then
        mem_suggest=$(echo "($mem_used_gb * 1.5 + 0.999)/1" | bc)
        echo "   ⚠ VERY LOW MEMORY EFFICIENCY (<10%)"
        echo "   - Consider reducing memory request to ~${mem_suggest}GB for similar jobs"
    elif (( $(echo "$memory_efficiency < 50" | bc -l) )); then
        mem_suggest=$(echo "($mem_used_gb * 0.75 + 0.999)/1" | bc) 
        echo "   ⚠ LOW MEMORY EFFICIENCY (<50%)"
        echo "   - Consider reducing memory request to ~${mem_suggest}GB for similar jobs"
    elif (( $(echo "$memory_efficiency < 98" | bc -l) )); then
        echo "   ⚠ GOOD MEMORY EFFICIENCY (>50% and <98%)"
        echo "   - Good use of the requested memory"
    else
        echo "   ⚠ VERY HIGH MEMORY EFFICIENCY (>98%)"
        echo "   - Good use of the requested memory"
        echo "   - Consider increasing memory request slightly to avoid potential out of memory job failures"
    fi
fi

# CPU efficiency check (only for CPU partition jobs)
if [[ "$partition_type" != "gpu" ]] && [ -n "$cpu_efficiency" ]; then
    if (( $(echo "$cpu_efficiency < 25" | bc) )); then
        echo "   ⚠ LOW CPU EFFICIENCY (<25%)"
        echo "     - Check if job is I/O bound or waiting on resources"
        echo "     - Consider reducing number of cores requested"
        echo "     - Consider optimising parallelisation or threading"
    elif (( $(echo "$cpu_efficiency < 50" | bc) )); then
        echo "   ⚠ MODERATE CPU EFFICIENCY (25-50%)"
        echo "     - Consider reducing number of cores requested"
        echo "     - Consider optimising parallelisation or threading"
    fi
fi

# Walltime efficiency check
if (( $(echo "$walltime_efficiency < 30" | bc) )); then
    echo "   ⚠ VERY LOW WALLTIME USAGE (<30% of requested)"
    echo "     - Consider reducing walltime limit for similar jobs"
fi

# Good efficiency notice
if [ "$exitcode" = "0" ] && [ -n "$memory_efficiency" ] && [ "$memory_efficiency" != "N/A" ] && [ -n "$cpu_efficiency" ]; then
    if (( $(echo "$memory_efficiency > 70 && $cpu_efficiency > 70" | bc) )); then
            echo "   ✓ Good resource efficiency!"
    fi
fi

echo "======================================================================================"
