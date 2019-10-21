+++ 
date = "2019-10-21"
title = "Apache Airflow at Devoted Health"
slug = "airflow-at-devoted-health" 
description = "how we develop, test, and deploy Airflow"
+++
![Airflow @ Devoted](/images/airflow_at_devoted.png)

[Apache Airflow](https://github.com/apache/incubator-airflow) is an open-source workflow orchestration tool. There are many posts available that explain the core concepts of Airflow (I recommend this [one](https://medium.com/@itunpredictable/apache-airflow-on-docker-for-complete-beginners-cf76cf7b2c9a)). This post assumes you have some familiarity with these concepts and focuses on how we develop, test, and deploy Airflow and Airflow DAGs at [Devoted Health](https://www.devoted.com). Devoted is a Medicare Advantage startup aimed at making healthcare easier, more affordable, and believes every member should be treated like we would treat a member of our own family.

## Airflow Deployment

*This part of the post discusses [Kubernetes](https://kubernetes.io/), [Helm](https://helm.sh/), [Terraform](https://www.terraform.io/), and [Docker](https://www.docker.com/), but since they are all their own complicated things, it does not go into detail about any of them.*

We have a very modern technology stack at Devoted, so of course, we run Airflow on Kubernetes. This means we use Docker containers to deploy all of our Airflow infrastructure. We have a single Docker image that is used for the Airflow Web Server, Scheduler, and most of our Tasks. It has a core set of Python dependencies installed, and whenever an update is made, it is built and deployed to [Amazon ECR](https://aws.amazon.com/ecr/) via a CI job.

We deploy Airflow itself using a Helm chart (based on this one in [charts/stable](https://github.com/helm/charts/tree/master/stable/airflow)) that describes all of the Kubernetes resources (Deployments, Services, Persistent Volumes, etc.) we want for Airflow. We couple this with Terraform, which allows us to deploy a new instance of Airflow with a simple command like:

```shell
terraform apply --target=module.airflow
```

This command creates a RDS database, an EFS volume for DAG storage, a Kubernetes namespace, and Airflow Scheduler and Web Server pods. 

Notice that I didn’t mention any Airflow Workers. We recently migrated to Airflow's [Kubernetes Executor](https://airflow.apache.org/kubernetes.html), which has no permanent Workers and no Redis/Celery requirement for distributing work. Instead, every Airflow Task is run in its own pod. This means we can allocate resources for each Task rather than just having our workers sized for our most resource intensive jobs. Additionally, we can have a different Docker image for each Task. If a Data Scientist writes a complicated Machine Learning job that has many dependencies, this allows us to keep those separate from our core Airflow image. We’ve been running this setup for a few months now and it has been great for us so far.

**TL;DR**

* We use Terraform and Helm to deploy Airflow to Kubernetes.
* We run Airflow using the Kubernetes Executor to allow for maximum flexibility in our DAG design and resource allocation.

## DAG Development

At Devoted, we have many different people working on Airflow DAGs including a team of 8 Data Scientists (they’re awesome and they’re [hiring](https://jobs.lever.co/devoted/d0758ba1-3bde-42c6-9981-b28f2041e461)!). This has led to some unique challenges since often different people are working on different parts of the same DAG. 

We’ve solved this by developing an internal tool that allows each developer to spin up their own Airflow instance on Kubernetes (these are smaller than our Staging/Production environments) along with their own clone of our data warehouse (it’s a [Snowflake](https://www.snowflake.com/) thing, you should use Snowflake it is also awesome). This tool is called `devflow` because I am not creative when it comes to naming things except my cats ([Mac & Cheese](https://www.instagram.com/mac.cheese.cat/)). It wraps Helm, kubectl, and Terraform into a few simple commands so developers can run things like `devflow start` to start up their dev environment and `devflow sync` to deploy their local changes to their instance.

Besides helping avoid collisions in DAG development, this setup allows developers to use the same technology and environments in Dev that we use in Staging/Prod creating far less “it works on my machine” scenarios.

In addition to `devflow`, the Data Engineering team at Devoted has built another internal tool to streamline DAG development called `DAG Builder`. This library provides a simple interface for creating a new data pipeline in Airflow. Developers write a DDL query for an end table, a transformation in SQL or Python, and use a YAML file to describe the DAG. 

```yaml
dag: 'example_dag'
owner: 'Data Science'
schedule: '30 */4 * * *'
 
prep_schema: 'staging'
final_schema: 'warehouse'
base_path: 'warehouse/example_dag/'
 
tasks:
 dim_table:
   config_type: 'SqlTask'
   ddl: 'ddl/dim_table.sql'
   sql: 'extractors/dim_table.sql'
 
 fact_table:
   config_type: 'PythonTask'
   ddl: 'ddl/fact_table.sql'
   python: 'extractors/fact_table.py'
   deps:
     - dim_table
```

The example above generates a DAG that populates two tables, one dependent on the other, and automatically includes alerting, monitoring, support for integration testing, and more. This approach has allowed us to standardize our DAGs, which makes adding new features/enhancements to all DAGs (like the data validation tests below) much easier and improves developer efficiency as Data Scientists can easily understand and work on pipelines they didn’t originally write.

**TL;DR**

* Every developer at Devoted using Airflow gets their own dev instance.
* Standardizing DAGs allows Devoted to quickly add new features to all pipelines.

## Testing & Validation

Ok, I’ve talked about how we deploy Airflow and develop DAGs, but how do we make sure they’re working and accurate? Well, obviously, it’s everyone’s favorite thing to the rescue ...testing!

We use three different types of tests to verify that DAGs are working as expected.

#### Unit Tests

All DAGs must pass a suite of unit tests in our CI pipeline before being deployed. These are tests that can be run independently of other resources and include a smoke test that validates every DAG can be imported into the Airflow DagBag (I will never not laugh when I type that) as well as tests for any python code used in our DAGs. We use `pytest` to run these and we feel they’re table stakes for testing.

#### Integration Tests

This set of tests interact with other resources, which is obviously very important for a workflow tool like Airflow that connects to a bunch of platforms. Thanks to the efforts of one of our Data Engineers, Julie Rice, we run end-to-end tests for most DAGs in another CI pipeline. This helps validate that our SQL doesn’t have errors and things like complicated CASE statements (who doesn’t love these?) produce the expected results in our data warehouse. This was a challenging thing to implement, but we believe the investment will pay off in increasing Developer confidence as they make changes. 

#### Data Validation

The third form of testing we use is the only one that doesn’t happen before deployments. Instead, data validation is done within each DAG at run-time. We have a set of standard tasks that allow Airflow Developers to specify things like “this column should be unique”, “this one should never be NULL”, or “this should have a record count greater than X”. This is the final protection we have against allowing our internal users to access reports with incorrect data.

**TL;DR**

* Every Airflow DAG is tested before being deployed.
* We run end-to-end Integration Tests for most DAGs to reduce errors in Production.
* Data validation tasks run in each DAG to prevent incorrect data from getting into reports.

## DAG Deployment

We use a single [AWS EFS](https://aws.amazon.com/efs/) volume to persistently store Airflow DAGs (and plugins) for each environment. It is shared amongst all of the pods in the Airflow namespace (Web Server, Scheduler, and Tasks), so we only need to push new/updated DAGs to one place for all of our resources. This is done via a simple CI job that runs once DAGs have passed our test suite described above. No old-school release cycle here, we deploy whenever a new change is ready, which happens many times per day.

**TL;DR**

* This section is only a couple of sentences, just read it. :) 

## Monitoring

I’ve gone over how we develop, test, and deploy Airflow, but saved my favorite for last. Monitoring AKA how we, the team in charge of keeping Airflow running, sleep soundly at night knowing it is, in fact, running.

Our first line of defense against OpsGenie Alerts is a feature of Kubernetes called Liveness Checks. This allows you to signal to Kubernetes that your container is in a bad state and should be restarted. As all good technologists know, sometimes turning it off and on again is all it takes to fix something. For the Web Server, we simply use Airflow’s `/health` endpoint to verify it is up and running. For the Scheduler, we have a custom script that says the Scheduler needs to be restarted if there are more than 0 queued tasks, 0 running tasks, and 0 tasks completely recently.

Liveness are nice for saving someone from a simple fix, but they’re not really monitoring. For that, the core Airflow project is heavily instrumented with [statsd](https://github.com/apache/airflow/blob/master/airflow/stats.py#L106) metrics. We send all of these to [DataDog](https://www.datadoghq.com) and use their dashboards to tell us about Airflow’s CPU and memory usage. Additionally, we have several DataDog monitors setup there that alert the team if key DAGs haven’t reported success in the expected time period. Airflow has a SLA feature that does something similar, but this allows us to decouple monitoring from the service.

**TL;DR**

* We use Kubernetes Liveness Checks to restart pods that are in a bad state without human intervention.
* We use DataDog to monitor Airflow resource usage and get alerts about DAG SLAs.

If working on and helping improve Devoted Health’s Airflow setup sounds interesting to you, we’re [hiring](https://jobs.lever.co/devoted/)!



