# Draft SLURM Usage Post Script
This is a draft script that aims to be implemented at the end of all SLURM jobs on Setonix, similar to NCI's jobs post script. 

## Current Usage
In the current test form, run the script with the following instructions. The job ID should be a job that has completed running. It can be any job from any user. 

```bash
bash postscript.sh <jobID>
```
Please avoid running the script in a loop with many iterations as this will likely stress SLURM and result in a slowdown on the system for other users.

## Current output view
Example output view. This script also provides feedback on job efficiency for the user to consider. 

```bash
sbeecroft@setonix-01:/scratch/pawsey0001/sbeecroft/slurm_post_script> bash postscript.sh <job_id>
======================================================================================
                  Resource Usage on 2025-11-21 13:16:03:
   Job Id:             <job_id>            Project: pawseyXXXX
   Partition:          work
   Exit Status:        0                       Job State: COMPLETED
   Service Units:      7.21
   Nodes Requested:    1
   NCPUs Requested:    1                       NCPUs Allocated: 2
   CPU Time Available: 07:12:36                CPU Time Used: 07:12:12
   Memory Requested:   999.999488MB            Memory Used: 454.600704MB
   Walltime Requested: 1-00:00:00              Walltime Used: 03:36:18
   Walltime Efficiency:15.02%
   CPU Efficiency:     99.90%                  Memory Efficiency: 45.46%
   GCDs Requested: 0                      
-------------------------------------------------------------------------------------
   Efficiency Analysis & Recommendations:

   ⚠ LOW MEMORY EFFICIENCY (<50%)
   - Consider reducing memory request to ~1GB for similar jobs
   ⚠ VERY LOW WALLTIME USAGE (<30% of requested)
     - Consider reducing walltime limit for similar jobs
======================================================================================
```

## Open for Feedback and Comments
This is an exercise in thorough testing and collecting user feedback. Please get in touch with requests, bugs, PRs etc as needed. 
