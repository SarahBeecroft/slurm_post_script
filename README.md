# Draft SLURM Usage Post Script
This is a draft script that aims to be implemented at the end of all SLURM jobs on Setonix, similar to NCI's jobs post script. 

## Current Usage
In the current test form, run the script with the following instructions. The job ID should be a job that has completed running. It can be any job from any user. 

```bash
bash postscript.sh <jobID>
optional flags
--format text|csv|json
--help
--no-csv-header
 --quiet
```
Please avoid running the script in a loop with many iterations as this will likely stress SLURM and result in a slowdown on the system for other users.

## Current output view
Example output view. This script also provides feedback on job efficiency for the user to consider. 

```bash
sbeecroft@setonix-01:/scratch/pawsey0001/sbeecroft/slurm_post_script> bash postscript.sh <job_id>
======================================================================================
Usage report generated on 2026-03-25 13:37:04:

JOB DETAILS

   Job Id:             xxxxx                   Project:     xxxxxx
   Exit Status:        0                       Job State:   COMPLETED
   Job Submitted:      2024-01-19 10:52:57     Job Started: 2024-01-19 10:52:59
   Job Ended:          2024-01-19 11:24:11     Partition:   work

RESOURCE USAGE

   Nodes Requested:    1                       GCDs Requested:  0
   NCPUs Requested:    2                       NCPUs Allocated: 6
   CPU Time Available: 06:14:24                CPU Time Used:   00:59:45
   Memory Requested:   10GB                    Memory Used:     1.48GB
   Walltime Requested: 12:00:00                Walltime Used:   00:31:12

EFFICIENCY METRICS

   Memory Efficiency:  14.76%                  Service Units Used:  3.12
   CPU Efficiency:     15.96%                  Walltime Efficiency: 4.33%
-------------------------------------------------------------------------------------
   Efficiency Analysis & Recommendations:

    LOW MEMORY EFFICIENCY (<50%)
   - Consider reducing memory request to ~3GB for similar jobs
    LOW CPU EFFICIENCY (<25%)
     - Check if job is I/O bound or waiting on resources
     - Consider reducing number of cores requested
     - Consider optimising parallelisation or threading
    VERY LOW WALLTIME USAGE (<30% of requested)
     - Consider reducing walltime limit to around ~0.78 hours for similar jobs
======================================================================================
```

## Open for Feedback and Comments
This is an exercise in thorough testing and collecting user feedback. Please get in touch with requests, bugs, PRs etc as needed. 
