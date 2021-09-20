# Creating a Nextflow Pipeline on Palmetto

In this section we will show you how to take a workflow, which has been implemented as a series of job scripts, and implement the workflow as a Nextflow pipeline.

## Installing Nextflow on Palmetto

Installing Nextflow is very easy, you can do it right from your home directory:
```bash
curl -s https://get.nextflow.io | bash

./nextflow run hello
```

You can then do something like this to run `nextflow` like a normal program:
```bash
mkdir ~/bin
mv ./nextflow ~/bin
export PATH=${PATH}:${HOME}/bin

nextflow run hello
```

Alternatively, you can use the `install-nextflow.sh` script from [pbs-toolkit](https://github.com/bentsherman/pbs-toolkit) to install nextflow as a module:
```bash
wget https://raw.githubusercontent.com/bentsherman/pbs-toolkit/master/modules/install-nextflow.sh
chmod +x install-nextflow.sh
./install-nextflow.sh 21.04.3

module use ${HOME}/modules
module load nextflow/21.04.3
nextflow run hello
```

## An Example Workflow

Now let's start with an example workflow that we will convert into a Nextflow pipeline. We will use [KINC](https://github.com/SystemsGenetics/KINC), a bioinformatics application for constructing gene co-expression networks. KINC is a high-performance MPI/CUDA application but it also has a Python implementation which is easier to use for small experiments, so we will use the Python implementation. We have included the relevant Python scripts in this repo, as well as wrapper scripts for each step in the workflow. Each job script (`kinc-*.sh`) calls the corresponding Python script on an actual dataset, and can be run locally or submitted as a PBS job.

To run the entire workflow we would have to do the following:
```bash
# create synthetic input dataset
qsub pbs/kinc-make-inputs.sh

# (wait for job to finish)

# perform similarity step
qsub pbs/kinc-similarity.sh

# (wait for job to finish)

# perform threshold step
qsub pbs/kinc-threshold.sh

# (wait for job to finish)

# perform extract step
qsub pbs/kinc-extract.sh

# (wait for job to finish)

# make plots of co-expression network
qsub pbs/kinc-make-plots.sh
```

As you can see, this process would be very tiresome. We essentially have to _babysit_ the workflow from beginning to end, waiting for each step to finish so we can submit the next one, backtracking any time something fails. All of this work will produce a single co-expression network. Can you imagine if we wanted to construct 100 different networks? It would be a nightmare.

Now our example workflow is small enough that we could just have one job script that runs every step end-to-end, but this won't always work in practice. You might not be able to perform your entire workflow within the max walltime of 72 hours on Palmetto. Or, different steps may have different resource requirements, so packing everything into one job script would be very wasteful. So we really need a way to manage multi-step workflows at scale, including launching jobs automatically, handling data dependencies, and recovering from job failures. Nextflow will do all of these things for us and more.

## Creating a Nextflow Pipeline

In this section we will walk you through the process of converting our job scripts into a Nextflow pipeline at a high level.

### Processes

The first step is to define the tasks in our workflow. Our KINC workflow is pretty simple, it consists of five steps in sequence:

1. Generate example input dataset
2. Compute similarity matrix
3. Compute similarity threshold
4. Extract co-expression network
5. Visualize pairwise scatter plots

We will define each step as a __process__ in our Nextflow pipeline. Each process will in turn generate a PBS job for its task. he skeleton of our pipeline script will look like this:
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

process make_plots {
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

python3 bin/make-input.py \
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

        make-input.py \
            --n-samples \${N_SAMPLES} \
            --n-genes \${N_GENES} \
            --n-classes \${N_CLASSES} \
            --dataset \${EMX_FILE} \
            --transpose
        """
}
```

And so on for each process. Two small things we changed here:

1. We escaped our Bash variables to distinguish them from Nextflow variables. More on this later.
2. We call the Python script like a standalone program. Any script in the `bin` directory can be called this way, as long as it has the proper permission bits and shebang. The Python scripts are already set up this way.

### Data Dependencies

When using the job scripts, we simply run each step in order, and since everything is in the same directory, every script has access to every data file. In Nextflow, since we define each step in its own "process", we must explicitly define the inputs and outputs for each process. Once we have defined all of the steps, we will be able to hook them up, but for now, let's just figure out what we need to do for the `make_input` process. This step takes a filename and creates an expression matrix with that name, so we will define the inputs and outputs as follows:
```
process make_input {
    input:
        val(emx_file)

    output:
        path(emx_file), emit: emx_files

    script:
        """
        N_SAMPLES=1000
        N_GENES=100
        N_CLASSES=2

        make-input.py \
            --n-samples \${N_SAMPLES} \
            --n-genes \${N_GENES} \
            --n-classes \${N_CLASSES} \
            --dataset ${emx_file} \
            --transpose
        """
}
```

The input is a string, so we declare it as a `val`. The output is an actual file (with the same name as the input) so we declare it as a `path`. Furthermore, we declare that the output be available to other processes under the name `emx_files`. We'll see how this part is used in a moment.

Notice that we say `${emx_file}` in the script to denote that `emx_file` is a Nextflow variable and not a Bash variable. Think of the script as a template: each time Nextflow launches an instance of this process, it populates this script with the values of the Nextflow variables for that instance. For example, if we configured the workflow to create multiple input files in parallel, Nextflow would launch a separate task for each filename, so the script for each task would contain its corresponding filename in place of `${emx_file}`.

Now see if you can define the remaining steps based on this example.

### Defining the Workflow

Once you have defined a process for each step, all that's left is to hook them up to each other. To do this, we define a __workflow__ block:
```
nextflow.enable.dsl=2

workflow {
  ...
}
```

In comparison to other scripting languages, the workflow block is kind of like the "main" function and processes are kind of like functions. Nextflow uses a mechanism called __channels__ to pass data between processes. A channel can contain any basic data type, including numbers, strings, lists, maps, and files. In a workflow block, you can define channels from literal values, you can pass channels as inputs to a process, and you can access the outputs of a process as channels. So channels are basically pipes that allow you to pass data from one process to another.

In the first part of the workflow, we want to run `make_input` to create a single emx file called "example.emx.txt". Here is how we write it:
```
workflow {
    emx_files = Channel.fromList([ "example.emx.txt" ])

    make_input(emx_files)
    emx_files = make_input.out.emx_files
}
```

We define a channel with a single value in it, we call `make_input` like a function, with the `emx_files` channel as an input, and we set `emx_files` to the output channel of `make_input`.

This code looks a lot like normal code, but there are a few key differences to understand here:

- A process can only be invoked once in a workflow block.

- When a process is invoked, Nextflow will execute a separate instance of the process (i.e. task) for each item in the input channel, in parallel if possible.

- If a process has multiple input channels, each task consumes a value from each channel. Just like pipes!

- If two processes are invoked, and neither process depends on the other, Nextflow will automatically execute tasks for both processes in parallel.

In other words, a Nextflow workflow is not a list of step-by-step instructions, rather it is a _network of processes and channels_. When you run the pipeline, Nextflow builds this network, then it starts feeding data into the input channels, and then it continuously executes tasks in parallel until there is nothing left to execute. This approach works the same for 1 input file or 10,000 input files, on a computer with 1 CPU or a cluster with 10,000 CPUs.

But before we are overwhelmed by the immense power of dataflow programming, first let's finish writing this workflow. See if you can define the remaining steps based on the above example.

_Note: We include the `nextflow.enable.dsl=2` to enable Nextflow's DSL 2 syntax, which allows us to use features like the workflow block. In the original Nextflow syntax, there is no workflow block but you have to define a lot of the same channel logic inside and between the processes, which is a real mess. We recommend you stick with DSL 2._

### Configuration Parameters

Often we would like to be able to provide custom options to our code without having to change the code directly. With Nextflow you can define these options in a configuration file called `nextflow.config`. This config file has many sections, one of which is the `params` section. We can define all of our runtime options in `nextflow.config` instead of hard-coding them into the pipeline script:

__nextflow.config__
```
params {
    n_samples = 1000
    n_genes = 100
    n_classes = 2
    emx_file = "example.emx.txt"

    ...
}
```

__main.nf__
```
workflow {
    emx_files = Channel.fromList([ params.emx_file ])
    ...
}

process make_input {
    input:
        val(emx_file)

    output:
        path(emx_file), emit: emx_files

    script:
        """
        make-input.py \
            --n-samples ${params.n_samples} \
            --n-genes ${params.n_genes} \
            --n-classes ${params.n_classes} \
            --dataset ${emx_file} \
            --transpose
        """
}
```

Now you try to set up the params for the other processes!

### Saving Output Data

When you execute a Nextflow pipeline, Nextflow creates a `work` directory and executes each process in it's own directory inside `work`, so that each process can be isolated. Any files created by the process will exist in that process directory, so if you want any outputs to show up in the top-level directory, you have to __publish__ them. This part is easy, we just add the `publishDir` directive to each process:
```
process make_input {
    publishDir "${params.output_dir}"

    ...
}
```

This way, every file defined in a process output will be saved to the top-level output directory via hardlink. You can further configure this directive to do a copy or symlink, or only publish certain types of files, and so on.

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
    palmetto {
        process {
            executor = "pbspro"
            cpus = 2
            memory = 8.GB
            time = 24.h

            module = "anaconda3/5.1.0-gcc"
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

The `standard` profile is for when we are using our desktop (or just a compute node on Palmetto), and the `palmetto` profile is for when we want to use Palmetto through `qsub`. Note a few key differences in the `palmetto` profile: (1) we use the `pbspro` executor instead of `local`, (2) we specify a walltime of 24 hours for each job whereas on a local machine our tasks have no time limit, (3) we specify that the `anaconda3` module should be loaded whereas on a local machine we would assume it is already installed. Notice that these settings essentially replace the `#PBS` directives and `module` commands in our original job scripts. Nextflow will actually generate these same commands for us every time it launches a task.

### Collecting Performance Data

When you run a Nextflow pipeline, Nextflow can automatically generate several reports with information about how the pipeline ran. In particular there are three types of reports:
- Execution report: Summary, resource usage, and task list for the workflow run
- Timeline report: Waterfall-style timeline of workflow tasks
- Trace report: Tab-delimited text file of performance data for each task that was executed

We can enable these reports in our `nextflow.config`:
```
report {
    enabled = true
    file = "${params.output_dir}/reports/report.html"
}

timeline {
    enabled = true
    file = "${params.output_dir}/reports/timeline.html"
}

trace {
    enabled = true
    fields = "task_id,hash,native_id,process,tag,name,status,exit,module,container,cpus,time,disk,memory,attempt,submit,start,complete,duration,realtime,queue,%cpu,%mem,rss,vmem,peak_rss,peak_vmem,rchar,wchar,syscr,syscw,read_bytes,write_bytes"
    file = "${params.output_dir}/reports/trace.txt"
    raw = true
}
```

In practice the execution report is the most useful for manually inspecting what happened during a workflow run, and the trace report can be loaded directly into a spreadsheet program for data analysis.

## Going Further

The completed Nextflow pipeline files for this example are included in this repo. Use these files to check your work as you complete this exercise, and feel free to use them as a reference when building your own pipelines.

This example showed you how to convert a basic workflow into a Nextflow pipeline. For more in-depth examples, check out the Nextflow pipelines at the [SystemsGenetics](https://github.com/SystemsGenetics) Github org as well as [nf-core](https://github.com/nf-core).

The example pipeline here is based on the [KINC-nf](https://github.com/SystemsGenetics/KINC-nf) pipeline. Consult the original pipeline to see how to use more advanced features, including chunking and merging, running MPI jobs, using GPUs, using Docker / Singularity, and more. Refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/index.html) for more information.