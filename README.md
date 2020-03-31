# Using Nextflow on Palmetto

In this gist we will show you how to take a workflow, which has been implemented as a collection of job scripts, implement the workflow as a Nextflow pipeline, and execute it on an HPC cluster.

## Workflow Managers

The [Palmetto cluster](https://www.palmetto.clemson.edu/) at Clemson University provides access to thousands of compute nodes through the PBS scheduler. To use the cluster, you have to write a shell script that performs your computations and use `qsub` to submit the script to the cluster, additionally specifying what resources you need. As your computational work becomes more complex, you may find yourself writing long job scripts, splitting the work into multiple scripts that run in sequence, or writing meta-scripts that submit many jobs in parallel. What you really have now is a __workflow__ (or __pipeline__), which is simply a process with multiple steps.

Workflows are really hard to manage if you have to submit and monitor every step of the process yourself. Sometimes jobs fail, or you forget to check on them for a few days which wastes a lot of time. The solution is to use a __workflow manager__, which is a tool that simply runs your workflows for you. To use a workflow manager, you define your workflow as a __task graph__, which is a list of the steps in your workflow and the dependencies between each step. The workflow manager takes the task graph and executes it by automatically submitting jobs, monitoring them, possibly re-submitting them if they fail, and moving through each step in the workflow until it reaches the end, at which point you have your final results.

## Choosing a Workflow Manager

If you have complicated workflows then this probably sounds a lot better, doesn't it? That's because it is. With a workflow manager you can create workflows as large and complex as you want, and then execute them with a single command. Because workflows as a concept are so powerful and applicable to many fields, [everyone and their mother](https://github.com/pditommaso/awesome-pipeline) has made their own workflow manager. Here are just some highlights from the above list, just to illustrate the variety of ways in which workflows are used in software:

- Build automation: Make, Biomake, Drake, Snakemake
- Computational graphs: Tensorflow, PyTorch, Theano, Dask
- Data analytics: Airflow, Luigi
- Notebook environments: Binder, Jupyter
- Scientific workflows: Bpipe, Cromwell, Nextflow, Popper, Toil
- Workflow platforms: Galaxy, KNIME, Pegasus, Apache Taverna, DolphinNext
- Workflow languages: Cuneiform, CWL, WDL, YAWL

So there are many paradigms through which to use workflows, and many options for workflow managers, and it is important to choose the right workflow manager for you. Understand that most workflow managers were developed for a particular domain, such as bioinformatics or DevOps, and so they may be specialized for that domain. Some workflow managers allow you to define workflows through a GUI (e.g. Galaxy), some through a specific programming language (e.g. Airflow with Python), some through a configuration file (e.g. Popper), and some through a DSL (e.g. Nextflow). Some workflow managers can run on your laptop, some can run on your HPC cluster, some can run in the cloud or on Kubernetes. These are some of the primary distinctions you can use to help determine which workflow manager to use.

## So Why Nextflow?

In our lab we chose to use Nextflow for the following reasons:

- Nextflow was originally developed with bioinformatics in mind, and we are a bioinformatics lab, however in practice it can be used to write scientific workflows in any domain
- Nextflow pipelines are written in a DSL, and the code for individual tasks can be written in any scripting language
- Nextflow can run on your laptop, on HPC systems, in the cloud and on Kubernetes. It can run practically anywhere!

While it is still important to review the available options before picking a workflow manager, we believe that Nextflow is an excellent choice for writing data pipelines of any kind.

## Installing Nextflow on Palmetto

Installing Nextflow is very easy, you can do it right from your home directory:
```bash
module add java/1.8.0
curl -s https://get.nextflow.io | bash

./nextflow run hello
```

You can then do something like this to run `nextflow` like a normal program:
```bash
mkdir ~/bin
mv ./nextflow ~/bin
export PATH=$PATH:$HOME/bin

nextflow run hello
```

Alternatively, you can use the `install-nextflow.sh` script from [pbs-toolkit](https://github.com/bentsherman/pbs-toolkit) to install nextflow as a module:
```bash
wget https://raw.githubusercontent.com/bentsherman/pbs-toolkit/master/modules/install-nextflow.sh
chmod +x install-nextflow.sh
./install-nextflow.sh 20.01.0

module add use.own
module add nextflow/20.01.0
nextflow run hello
```

## An Example Workflow

Now let's start with an example workflow that we will convert into a Nextflow pipeline. We will use [KINC](https://github.com/SystemsGenetics/KINC), a bioinformatics application for constructing gene co-expression networks. KINC is a high-performance MPI/CUDA application but it also has a Python implementation which is easier to use for small experiments, so we will use the Python implementation. A basic script `kinc-py.sh` is provided below which can perform the entire KINC workflow. For the purpose of this demonstration it also generates a small input dataset for you.

To get started, clone the KINC repo from Github:
```bash
git clone https://github.com/SystemsGenetics/KINC.git
```

And then download and run the example job script:
```bash
wget https://gist.githubusercontent.com/bentsherman/bb2643f500b0352a78e8f5bdf09b18a1/raw/4073f54c6f9547eb535097039617937ce39cfec9/kinc-py.sh
qsub kinc-py.sh
```

## Creating a Nextflow Pipeline

In this section we will walk you through the process of converting our job script into a Nextflow pipeline at a high level. For more detailed information, refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/index.html).

### Defining the Task Graph

The first step is to divide the existing workflow script into tasks. In this case, our KINC workflow simply consists of five steps in sequence:

1. Generate example input dataset
2. Compute similarity matrix
3. Compute similarity threshold
4. Extract co-expression network
5. Visualize pairwise scatter plots

For such a simnple example it may be alright to run everything in a single job. However, there are some issues:

- If the input dataset is large, the job may not be able to complete all five steps within the 72 hour walltime
- Each step in the workflow may have different resource requirements (CPU, memory, walltime), but the job script will have to request enough resources to satisfy all five steps
- In this example each step depends on the step before it, but in general a workflow could have tasks that could be executed in parallel, such as a chunk-and-merge strategy

For these reasons, our Nextflow pipeline will split these five steps each into separate tasks, or __processes__, which in turn will be run as five separate PBS jobs. The skeleton of our pipeline script will look like this:
```
process make_input {
  ...
}

process similarity {
  ...
}

process threshold {
  ...
}

process extract {
  ...
}

process visualize {
  ...
}
```

For each process, we will define the script that the process should run, so we can transfer the code for each step directly into the corresponding process. For example, for the first step:
```bash
# generate example input dataset
N_SAMPLES=1000
N_GENES=100
N_CLASSES=2
EMX_FILE="example.emx.txt"

python ${KINC_PATH}/scripts/make-input-data.py \
	--n-samples ${N_SAMPLES} \
	--n-genes ${N_GENES} \
	--n-classes ${N_CLASSES} \
	--dataset ${EMX_FILE} \
	--transpose
```

Becomes:
```
process make_input {
	script:
		"""
		N_SAMPLES=1000
		N_GENES=100
		N_CLASSES=2
		EMX_FILE="example.emx.txt"

		python \${KINC_PATH}/scripts/make-input-data.py \
			--n-samples \${N_SAMPLES} \
			--n-genes \${N_GENES} \
			--n-classes \${N_CLASSES} \
			--dataset \${EMX_FILE} \
			--transpose
		"""
}
```

And so on for each process. Note that we had to escape each `$` character to specify that each variable is a Bash variable rather than a Nextflow variable, as we will see in the coming steps.

### Data Dependencies

This part requires you to think a bit differently. When we ran the job script, everything ran in the same directory and all of the intermediate files were defined at the beginning. In a Nextflow pipeline, you must explicitly define the inputs and outputs to each individual process, using __channels__. A channel is essentially a queue which passes data from one process to another. It can contain literal values like numbers and strings and lists, or it can contain files. Each process can have input channels and output channels. When all of the input channels for a process have a value, Nextflow takes a value out of each channel and launches the process with those values, repeating until one of the channels are empty. When a process finishes, Nextflow puts the each process output into its corresponding channel (if it has one) which will in turn feed into another process.

In other words, channels define the __data dependencies__ between processes, and Nextflow uses them to determine when to launch processes. In our case, the channels will cause Nextflow to launch each process one after the other, but as an example we could modify the pipeline to create multiple input files and process each input file in parallel.

So let's keep working on the `make_input` process. This step creates an expression matrix which is used by downstream processes, so we'll provide the emx filename as an input and the emx file as an output:
```
process make_input {
	input:
		val(emx_file) from Channel.value("example.emx.txt")

	output:
		file(emx_file) into EMX_FILES_FROM_MAKE_INPUT

	script:
		"""
		N_SAMPLES=1000
		N_GENES=100
		N_CLASSES=2

		python \${KINC_PATH}/scripts/make-input-data.py \
			--n-samples \${N_SAMPLES} \
			--n-genes \${N_GENES} \
			--n-classes \${N_CLASSES} \
			--dataset ${emx_file} \
			--transpose
		"""
}
```

The input channel contains a single value, the name of the expression matrix, so this process will execute once. The output channel contains the emx file that is created. Notice that we say `${emx_file}` to denote that `emx_file` is a Nextflow variable and not a Bash variable. Think of the script as a template: each time Nextflow launches an instance of this process, it populates this script with the values of the Nextflow variables for that instance. For example, if we wanted to try the idea we said earlier and create multiple input files in parallel, all we would have to do is modify the input channel to provide multiple values. Nextflow would launch a separate task for each filename, so the script for each task would contain its corresponding filename in place of `${emx_file}`.

One more important point: the emx file created by `make_input` is used by multiple downstream processes, but you can only use a Nextflow channel twice, once for where it comes from and once for where it goes to. So to pass the emx file to multiple destinations, we have to fork it into multiple channels:
```
EMX_FILES_FROM_MAKE_INPUT
	.into {
		EMX_FILES_FOR_SIMILARITY;
		EMX_FILES_FOR_THRESHOLD;
		EMX_FILES_FOR_EXTRACT
	}
```

This code is an example of an __operator__, which is any function that transforms one channel into another. We define this part in the pipeline script but after the `make_input` process. Now whenever an emx file comes out of `make_input`, it will be sent to each process that needs it. Easy! Now see if you can hook up the rest of the processes.

### Configuration Parameters

Often we would like to be able to provide custom options to our code without having to change the code directly. With Nextflow you can define these options in a configuration file called `nextflow.config`. This config file has many sections, one of which is the `params` section. We can define all of our runtime options in `nextflow.config` instead of hard-coding them into the pipeline script:

__nextflow.config__
```
params {
	input {
		n_samples = 1000
		n_genes = 100
		n_classes = 2
		emx_file = "example.emx.txt"
	}

	...
}
```

__main.nf__
```
process make_input {
	input:
		val(emx_file) from Channel.value(params.input.emx_file)

	output:
		file(emx_file) into EMX_FILES_FROM_MAKE_INPUT

	script:
		"""
		python \${KINC_PATH}/scripts/make-input-data.py \
			--n-samples ${params.input.n_samples} \
			--n-genes ${params.input.n_genes} \
			--n-classes ${params.input.n_classes} \
			--dataset ${emx_file} \
			--transpose
		"""
}
```

Now you try to set up the params for the other processes!

### Inputs and Outputs

When you execute a Nextflow pipeline, Nextflow creates a `work` directory and executes each process in it's own directory inside `work`, so that each process can be isolated. Any files created by the process will exist in that process directory, so if you want any outputs to show up in the top-level directory, you have to __publish__ them. This part is easy, we just add the `publishDir` directive to each process:
```
process make_input {
	publishDir "${params.output.dir}"

	...
}
```

This way, every output file as defined by an output channel will also be sent to the top-level output directory via hardlink. You can further configure this directive to do a copy or symlink, or only publish certain types of files, and so on.

### Defining an Error Strategy

Although many job failures are caused by bugs and user error, sometimes jobs just fail because of transient system problems and other random things. Nextflow can deal with this by retrying a job if it fails and terminating only if the job keeps failing a certain number of times. That way the workflow doesn't have to crash just because one job fails once but would have worked the second time. We can do this in the `process` section of `nextflow.config`:
```
process {
	errorStrategy = "retry"
	maxRetries = 2
}
```

The `errorStrategy` directive specifiies what to do if a job fails, and `maxRetries` specifies how many times to retry before terminating the workflow. The above settings will cause Nextflow to fail only if a job fails three times in a row. You can also set `errorStrategy` to `terminate` (Nextflow will fail immediately if any job fails) or `ignore` (Nextflow will ignore the failed job and keep going).

Selecting an appropriate error strategy can be very helpful depending on what you're doing. For example, when debugging a workflow it is generally better to use `terminate` so that when something fails you see the error immediately. On the other hand, if you're processing a large amount of data and it's okay if some of the data gets thrown out, using `ignore` might be better so that you can get at least some results quickly.

### Execution Profiles

Often we would like to be able to run the same workflow in different environments. For example we might want to use our desktop to test and debug the workflow and do small runs, and then use an HPC system or the cloud to do large runs. But there are often minor differences in execution on one system versus another, even if the code is largely the same. Nextflow allows us to capture these differences through __profiles__. With a profile you can define settings for a specific environment, and then when you run your pipeline, you just use the profile you created for that particular environment. In our case we have two environments, desktop and Palmetto, so we will create two profiles in `nextflow.config`:
```
profiles {
	pbs {
		process {
			executor = "pbspro"
			cpus = 2
			memory = 8.GB
			time = "24h"

			module = "anaconda3"
		}
	}

	standard {
		process {
			executor = "local"
			cpus = 2
			memory = 8.GB
		}
	}
}
```

The `standard` profile is for when we are using our desktop (or just a compute node on Palmetto), and the `pbs` profile is for when we want to use Palmetto through `qsub`. Note a few key differences in the `pbs` profile: (1) we use the `pbspro` executor instead of `local`, (2) we specify a walltime of 24 hours for each job whereas on a local machine our tasks have no time limit, (3) we specify that the `anaconda3` module should be loaded whereas on a local machine we would assume it is already installed. Notice that these settings essentially replace the `#PBS` directives and `module` commands at the beginning of our original job script. Nextflow will actually generate these same commands for us every time it launches a task.

### Collecting Performance Data

When you run a Nextflow pipeline, Nextflow can automatically generate several reports with information about how the pipeline ran. In particular there are three types of reports:
- Execution report: Summary, resource usage, and task list for the workflow run
- Timeline report: Waterfall-style timeline of workflow tasks
- Trace report: Tab-delimited text file of performance data for each task that was executed

We can enable these reports in our `nextflow.config`:
```
report {
	enabled = true
	file = "${params.output.dir}/reports/report.html"
}

timeline {
	enabled = true
	file = "${params.output.dir}/reports/timeline.html"
}

trace {
	enabled = true
	fields = "task_id,hash,native_id,process,tag,name,status,exit,module,container,cpus,time,disk,memory,attempt,submit,start,complete,duration,realtime,queue,%cpu,%mem,rss,vmem,peak_rss,peak_vmem,rchar,wchar,syscr,syscw,read_bytes,write_bytes"
	file = "${params.output.dir}/reports/trace.txt"
	raw = true
}
```

In practice the execution report is the most useful for manually inspecting what happened during a workflow run, and the trace report can be loaded directly into a spreadsheet program for data analysis.

## Using the Login VM

If you run this Nextflow pipeline with the `standard` profile on a compute node you'll be able to run for up to 72 hours. However if you use the `pbs` profile and have Nextflow submit jobs through `qsub`, the pipeline can run for as long as it needs. The problem is that in order to do this Nextflow must run on the login node for the duration of the workflow run, which will not work because long-running tasks on the login node are killed automatically. You might be able to get away with short runs but anything longer than a few minutes is likely to be killed.

Fortunately, the Palmetto cluster now has a feature called the [Login VM](https://www.palmetto.clemson.edu/loginvm), which is essentially a dedicated login node that you can provision for yourself. When you request a VM you will receive an IP address which you can use to access the VM via SSH or RDP. On this VM you can do whatever you want, but note that the login VMs have limited resources so you still should not run compute intensive jobs on them. Also, login VMs do not come with a fixed walltime but instead are killed when you release them, and they can be killed automatically by Palmetto if you leave it idle.

For running Nextflow pipelines, the best way to use the login VM is through __RDP__ rather than __SSH__, because your VM will not be killed if you have something running on RDP. This way, when you want to launch a long-running Nextflow pipeline, you can request a VM, login to the VM through an RDP client, launch the Nextflow pipeline in a terminal, and then you can disconnect from the VM and your pipeline will still be running on Palmetto. That way your local machine doesn't have to stay connected while the pipeline is running, you can turn it off for the weekend and your code will keep working for you! I have used this method to launch pipelines that run for a month or longer. For instructions on how to use the login VM through RDP, consult the login VM documentation linked above.

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

## Going Further

This example showed you how to convert a basic workflow into a Nextflow pipeline. For more in-depth examples, check out the Nextflow pipelines at the [SystemsGenetics](https://github.com/SystemsGenetics) Github org as well as [nf-core](https://github.com/nf-core).

The example pipeline here is taken from the [KINC-nf](https://github.com/SystemsGenetics/KINC-nf) pipeline. Consult the original pipeline to see how to use more advanced features, including chunking and merging, running MPI jobs, using GPUs, using Docker / Singularity, and more.

To see the completed Nextflow pipeline for this example, download them from the original Github Gist:
```bash
wget https://gist.github.com/bentsherman/bb2643f500b0352a78e8f5bdf09b18a1/raw/dfedc8183de8920e0679ab1772e6f1f4ec294ddd/main.nf
wget https://gist.github.com/bentsherman/bb2643f500b0352a78e8f5bdf09b18a1/raw/dfedc8183de8920e0679ab1772e6f1f4ec294ddd/nextflow.config
```