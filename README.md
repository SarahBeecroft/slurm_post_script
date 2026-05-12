# Job Summary for SLURM jobs with efficiency optmisation recommendations

Obtain job statistics, service unit usage, and efficiency metrics with a simple command. Recommendations will assist researchers in improving their runtime efficiency. This tool has multiple options for usage, which will be explained below. Due to limitations in SLURM reporting for the GPU partitions, functionality is limited for GPU efficiency calculations.

## Quick Start

The core functionality is running the tool on a single completed job. It can be any job from any user.
Command:
```bash
bash job_summary.sh <jobID> <flags if needed>
```

Example output:

```bash
sbeecroft@setonix-05:~> bash job_summary.sh 5484848
======================================================================================
Usage report generated on 2026-05-07 16:13:49:

JOB DETAILS

   Job Id:             5484848                 Project:     pawsey0391
   Exit Status:        0                       Job State:   COMPLETED
   Job Submitted:      2023-11-13 05:59:03     Job Started: 2023-11-13 06:02:13
   Job Ended:          2023-11-13 07:37:36     Partition:   work

RESOURCE USAGE

   Nodes Requested:    1                       GCDs Requested:  0
   NCPUs Requested:    68                      NCPUs Allocated: 128
   CPU Time Available: 406:58:08               CPU Time Used:   107:59:54
   Memory Requested:   230GB                   Memory Used:     3.34GB
   Walltime Requested: 1-00:00:00              Walltime Used:   01:35:23

EFFICIENCY METRICS

   Memory Efficiency:  1.45%                   Service Units Used:  203.47
   CPU Efficiency:     26.54%                  Walltime Efficiency: 6.62%
-------------------------------------------------------------------------------------
   Efficiency Analysis & Recommendations:

    VERY LOW MEMORY EFFICIENCY (<10%)
   - Consider reducing memory request to ~6GB for similar jobs
    MODERATE CPU EFFICIENCY (25-50%)
     - Check if job is I/O bound or waiting on resources
     - Consider reducing number of cores requested
     - Consider optimising parallelisation or threading
    VERY LOW WALLTIME USAGE (<30% of requested)
     - Consider reducing walltime limit to around ~2.38 hours for similar jobs
======================================================================================
```

### Using additional flags

There are additional flags for added functionality:

The `--format` flag allows users to obtain data as text, CSV, or JSON format. Default is text, which is the example shown above. The CSV or JSON output is especially useful when collating usage metrics for many jobs for detailed analysis.
The `--quiet` flag suppresses the Efficiency Analysis & Recommendations section when format is text. It is not required for the CSV or JSON formats.
The `--no-csv-header` flag supresses the column headers from the output when using CSV format.

### Headers

For reference, when using the CSV format, the column headers are as follows
```bash
generated_at,job_id,project,partition,exit_status,job_state,nodes_requested,gcds_requested,ncpus_requested,ncpus_allocated,ncpus_allocated_raw,cpu_time_available,cpu_time_available_s,cpu_time_used,cpu_time_used_s,memory_requested,memory_requested_gb,memory_used,memory_used_gb,walltime_requested,walltime_used,walltime_requested_h,walltime_used_h,walltime_efficiency_pct,cpu_efficiency_pct,memory_efficiency_pct,service_units,job_submitted,job_started,job_ended
```

### Advanced Usage

If you have a lot of jobs to query for efficiency, you can run this tool in a simple loop. For example,

```bash
#!/bin/bash -l

for jobID in <list of IDs>
do
echo "processing jobID"
bash job_summary.sh jobID --format csv --no-csv-header >> metrics_summary.csv
done
```

## Tips and tricks

I'm seeing:
### Low CPU efficiency, high memory efficiency
- You might find that your CPU efficiency is very low but your memory efficiency is high. This might reflect a job that is memory bound. On the standard compute nodes, there is 1.8GB of memory per core. If you ask SLURM for 1 core but 5GB of memory, you will be assigned 3 cores because you're using 3 core's worth of memory. If you don't use those cores for computation, you might get a low CPU efficiency score just due to the nature of your job.

I'm seeing:
### Low CPU efficiency, low memory efficiency
- This might indicate that you have asked for more resources that you need. Consider lowering your resource request to SLURM. It's also worth considering if your job is doing a lot of I/O to disk. Moving the files that get the most I/O to /tmp on a compute node might give you a massive speedup.

I'm seeing:
### Unexpectly low CPU efficiency
- Is your job able to use the cores you're giving it?
For example, have you asked for 100 cores for a single threaded process? Not all codes can use multiple cores.
- Did you forget to set the number of threads/processes for your code in your command? Easy mistake to make!
- Is your process I/O bound? Your cores might be spending a lot of time waiting for reading and writing to happen on disk. In this case, moving the files that get the most I/O to /tmp on a compute node might give you a massive speedup.
Does your code scale well? Many mutli-threaded codes can efficiently use more cores up to a certain point, but then hit diminishing returns (Amdhal's Law). You might need to see what the literature says about the ideal number of cores to use, or do some tests yourself to see.
