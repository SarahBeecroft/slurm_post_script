# Draft SLURM Usage Post Script
This is a draft script that aims to be implemented at the end of all SLURM jobs on Setonix, similar to NCI's jobs post script. 

## Current Usage
In the current test form, run the script with the following instructions. The job ID should be a job that has completed running. It can be any job from any user. 

```bash
bash postscript.sh <jobID>
```
Please avoid running the script in a loop with many iterations as this will likely stress SLURM and result in a slowdown on the system for other users.

## Open for Feedback and Comments
This is an exercise in thorough testing and collecting user feedback. Please get in touch with requests, bugs, PRs etc as needed. 
