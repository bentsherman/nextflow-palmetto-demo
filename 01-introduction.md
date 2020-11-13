# Introduction

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