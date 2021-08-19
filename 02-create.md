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
./install-nextflow.sh 20.10.0

module use ${HOME}/modules
module load nextflow/20.10.0
nextflow run hello
```

## An Example Workflow

Now let's start with an example workflow that we will convert into a Nextflow pipeline. We will use [KINC](https://github.com/SystemsGenetics/KINC), a bioinformatics application for constructing gene co-expression networks. KINC is a high-performance MPI/CUDA application but it also has a Python implementation which is easier to use for small experiments, so we will use the Python implementation. We have included the relevant Python scripts in this repo, as well as wrapper scripts for each step in the workflow. Each job script (`kinc-*.sh`) calls the corresponding Python script on an actual dataset, and can be run locally or submitted as a PBS job.

To run the entire workflow we would have to do the following:
```bash
# create synthetic input dataset
qsub kinc-make-inputs.sh

# (wait for job to finish)

# perform similarity step
qsub kinc-similarity.sh

# (wait for job to finish)

# perform threshold step
qsub kinc-threshold.sh

# (wait for job to finish)

# perform extract step
qsub kinc-extract.sh

# (wait for job to finish)

# make plots of co-expression network
qsub kinc-make-plots.sh
```

As you can see, this process would be very tiresome. We essentially have to _babysit_ the workflow from beginning to end, waiting for each step to finish so we can submit the next one, backtracking any time something fails. All of this work will produce a single co-expression network. Can you imagine if we wanted to construct 100 different networks? It would be a nightmare.

Now our example workflow is small enough that we could just have one job script that runs every step end-to-end, but this won't always work in practice. You might not be able to perform your entire workflow within the max walltime of 72 hours on Palmetto. Or, different steps may have different resource requirements, so packing everything into one job script would be very wasteful. So we really need a way to manage multi-step workflows at scale, including launching jobs automatically, handling data dependencies, and recovering from job failures. Nextflow will do all of these things for us and more.

## Creating a Nextflow Pipeline

In this section we will walk you through the process of converting our job scripts into a Nextflow pipeline at a high level. For more detailed information, refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/index.html).

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

process make-plots {
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

        python3 bin/make-input.py \
            --n-samples \${N_SAMPLES} \
            --n-genes \${N_GENES} \
            --n-classes \${N_CLASSES} \
            --dataset \${EMX_FILE} \
            --transpose
        """
}
```

And so on for each process. Note that we had to escape each `$` character to specify that each variable is a Bash variable rather than a Nextflow variable. More on this later.

### Data Dependencies

This part requires you to think a bit differently. When we ran the job scripts, we handled data dependencies by simply running each step in the correct order. Nextflow, on the other hand, uses a mechanism called __channels__ to automatically determine the order of tasks. A channel is essentially a queue which passes data from one process to another. It can contain literal values like numbers and strings and lists, or it can contain files. Each process can have input channels and output channels. When all of the input channels for a process have a value, Nextflow takes a value out of each channel and launches the process with those values, repeating until one of the channels are empty. When a process finishes, Nextflow puts the each process output into its corresponding channel (if it has one) which will in turn feed into another process.

In other words, channels define the __data dependencies__ between processes, and Nextflow uses them to determine when to launch tasks for each process, regardless of the order in which we define them in the pipeline script. In our case, the channels will cause Nextflow to launch each process one after the other, but as an example we could modify the pipeline to create multiple input files and process each input file in parallel.

Let's keep working on the `make_input` process. This step creates an expression matrix which is used by downstream processes, so we'll provide the emx filename as an input and the emx file as an output:
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

        python3 bin/make-input.py \
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
        python3 bin/make-input.py \
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

## Going Further

The completed Nextflow pipeline files for this example are included in this repo. Use these files to check your work as you complete this exercise, and feel free to use them as a reference when building your own pipelines.

This example showed you how to convert a basic workflow into a Nextflow pipeline. For more in-depth examples, check out the Nextflow pipelines at the [SystemsGenetics](https://github.com/SystemsGenetics) Github org as well as [nf-core](https://github.com/nf-core).

The example pipeline here is based on the [KINC-nf](https://github.com/SystemsGenetics/KINC-nf) pipeline. Consult the original pipeline to see how to use more advanced features, including chunking and merging, running MPI jobs, using GPUs, using Docker / Singularity, and more.
