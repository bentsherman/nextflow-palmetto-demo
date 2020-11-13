# Running a Nextflow Pipeline on Palmetto

In this section we will show you how to run the Nextflow pipeline you just created on the Palmetto cluster.

## TL;DR

1. Request a VM via Palmetto [Login VM](https://www.palmetto.clemson.edu/loginvm)
2. Login to your VM through an RDP client, then log out
3. Request a Jupyter instance via Palmetto [JupyterLab](https://www.palmetto.clemson.edu/jupyterhub)
4. Open a terminal in JupyterLab
5. Append these settings to your `.bashrc`:
```bash
# alias for your login vm
alias loginvm="ssh <username>@<loginvm-ip-address>"

# use scratch1 for nextflow work directory
export NXF_WORK="/scratch1/${USER}/work"
```
6. Place your Nextflow pipeline in your home directory or your group's zfs directory
7. Login to your loginvm with your `loginvm` command
8. Create a screen with the `screen` command
9. Launch your Nextflow pipeline (with the `pbs` profile)
10. Detach from your screen (Ctrl-A D)
11. Exit your loginvm
12. Run `qstat -u ${USER}` every now and then to make sure your pipeline is running

## Using the Login VM

If you run this Nextflow pipeline with the `standard` profile on a compute node you'll be able to run for up to 72 hours. However if you use the `pbs` profile and have Nextflow submit jobs through `qsub`, the pipeline can run for as long as it needs. The problem is that in order to do this Nextflow must run on the login node for the duration of the workflow run, which will not work because long-running tasks on the login node are killed automatically. You might be able to get away with short runs but anything longer than a few minutes is likely to be killed.

Fortunately, the Palmetto cluster now has a feature called the [Login VM](https://www.palmetto.clemson.edu/loginvm), which is essentially a dedicated login node that you can provision for yourself. When you request a VM you will receive an IP address which you can use to access the VM via SSH or RDP. On this VM you can do whatever you want, but note that the login VMs have limited resources so you still should not run compute intensive jobs on them. Also, login VMs do not come with a fixed walltime but instead are killed when you release them, and they can be killed automatically by Palmetto if you leave it idle.

One quirk of the Palmetto Login VMs is that you must login to the VM once via RDP. Follow the instructions in the Login VM docs to login via RDP client, then log out. Doing this once will ensure that your VM runs indefinitely without being killed for inactivity. From this point on you can access your VM via SSH or via [JupyterLab](https://www.palmetto.clemson.edu/jupyterhub). I recommend using JupyterLab because it is a much easier and more powerful way to use Palmetto in general. You can edit files and view images in the browser but you can also open a terminal and do anything you would normally do through SSH. As it happens, you can SSH into your Login VM from your JupyterLab instance: `ssh <username>@<loginvm-ip-address>`. Furthermore, you can use the `screen` command to create a "virtual" terminal where you can run commands and then leave them running in the backgroud.

So here's the full process: login to JupyterLab, open a terminal, login to your Login VM, create a screen with the `screen` command, launch your Nextflow pipeline, detach from your screen via Ctrl-A D, exit your Login VM, close your JupyterLab browser tab, turn off your computer, go home. Your Nextflow pipeline will still be running on Palmetto without you having to be connected to Palmetto in any way. I have used this method to launch pipelines that run for a month or longer, and I almost never use a basic terminal anymore; I can do everything I need to do through Jupyterlab.

## Using Storage Responsibly

Like most HPC systems, Palmetto a home directory and scratch directories. Your home directory is permanent storage but you only get 100 GB and you're not supposed to run jobs in the home directory because everyone has to share it. On the other hand, the scratch storage is ~100 TB but it is not permanent; files older than 30 days get deleted. So we would like our jobs to use scratch storage while they run, but we need to make sure that our important data ends up in our home directory so that we don't have to worry about it getting deleted. We can configure Nextflow to do this quite easily:

1. Add this line to your `.bashrc`: `export NXF_WORK="/scratch1/${USER}/work"`
2. Do everything else in your home directory (or your group's zfs directory)

This way, all of your code, input data, and final output data will be in your home directory, but the jobs that Nextflow submits will always run in scratch storage. Nextflow will only use the home directory to save published output files, logs, and some cache metadata. And all of the intermediate files created by Nextflow jobs will be automatically deleted by the system as they age. You never even have to touch your scratch directory!

## Running the Nextflow Pipeline

To run our new pipeline, simply do:
```bash
nextflow run main.nf
```

This command is the same thing as doing:
```bash
nextflow -c nextflow.config run main.nf -profile pbs
```

So by default Nextflow will use the `nextflow.config` in the current directory and the `standard` profile. You can also use a different config file or pipeline script. These commands will run everything on whatever node you are currently on, be that the login node or a login VM or a compute node. To run the pipeline using `qsub`, get a login VM and use the `pbs` profile:
```bash
nextflow run main.nf -profile pbs
```

Now you should see it use the `pbspro` executor, and if you run `qstat -u $USER` in a different terminal, you should see Nextflow jobs queued up.

One more thing: if you launch a pipeline but it fails part of the way through, you can __resume__ the pipeline so that it recovers the jobs that already finished instead of running them again:
```bash
nextflow run main.nf -profile pbs -resume
```
