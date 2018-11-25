+++ 
date = "2018-11-21"
title = "Introducing dag-factory"
slug = "introducing-dag-factory" 
description = "generate Airflow DAGs from YAML configs"
+++

[Apache Airflow](https://github.com/apache/incubator-airflow) is "a platform to programmatically author, schedule, and monitor workflows." And it is currently having its *moment*. At [DataEngConf NYC 2018](https://www.dataengconf.com/speakers-nyc18), it seemed like every other talk was either about or mentioned Airflow. There have also been [countless](https://medium.com/making-meetup/data-pipeline-infrastructure-at-meetup-with-fewer-nightmares-running-apache-airflow-on-kubernetes-54cb8cdc69c3) [blog](https://medium.com/bluecore-engineering/were-all-using-airflow-wrong-and-how-to-fix-it-a56f14cb0753) [posts](https://bostata.com/post/built-to-scale-running-highly-concurrent-etl-with-apache-airflow/) about how different companies are using the tool and it even has a [podcast](https://soundcloud.com/the-airflow-podcast)!

A major use case for Airflow seems to be ETL or ELT or ETTL or whatever acronym we are using today for moving data in batches from production systems to data warehouses. This is a pattern that will typically be repeated in multiple pipelines. I recently gave a [talk](https://github.com/ajbosco/talks/blob/master/nyc-data-eng-meetup/airflow-at-do.pdf) on how we are using Airflow at my day job and use YAML configs to make these repeated pipelines easy to write, update, and extend. This approach is inspired by Chris Riccomini's seminal post on [Airflow at WePay](https://wecode.wepay.com/posts/airflow-wepay). Someone in the audience then asked "how are you going from YAML to Airflow DAGs?" My response was that we had a Python file that parsed the configs and generated the DAGs. This answer didn't seem to satisfy the audience member or myself. This pattern is very common in talks or posts about Airflow, but it seems like we are all writing the same logic independently. Thus the idea for [dag-factory](https://github.com/ajbosco/dag-factory) was born.

The [dag-factory](https://github.com/ajbosco/dag-factory) library makes it easy to create DAGs from YAML configuration by following a few steps. First, install dag-factory into your Airflow environment:

```
pip install dag-factory
```

Next create a YAML config in a place accessible to Airflow like this:

```
example_dag1:
  default_args:
    owner: 'example_owner'
    start_date: 2018-01-01
  schedule_interval: '0 3 * * *'
  description: 'this is an example dag!'
  tasks:
    task_1:
      operator: airflow.operators.bash_operator.BashOperator
      bash_command: 'echo 1'
    task_2:
      operator: airflow.operators.bash_operator.BashOperator
      bash_command: 'echo 2'
      dependencies: [task_1]
    task_3:
      operator: airflow.operators.bash_operator.BashOperator
      bash_command: 'echo 3'
      dependencies: [task_1]
```

Then create a `.py` file in your Airflow DAGs folder like this:

```
from airflow import DAG
import dagfactory

dag_factory = dagfactory.DagFactory("/path/to/dags/config_file.yml")

dag_factory.generate_dags(globals())
```

And :bam: you'll have a DAG running in Airflow that looks like this:

![example dag](/images/example_dag.png)

This approach offers a number of benefits including that Airflow DAGs can be created with no Python knowledge. This opens the platform to non-engineers on your team, which can be a productivity boost to both your organization and data platform.

[dag-factory](https://github.com/ajbosco/dag-factory) also allows engineers who do not regularly work with Airflow to create DAGs. These people frequently want to use the great features of Airflow (monitoring, retries, alerting, etc.), but learning about Hooks and Operators are outside the scope of their day-to-day jobs. Instead of having to read the docs (ewwww) to learn these primitives, they can create YAML configs just as easily as the cron job (ewwwwwwww) they were going to use. This will reduce the time spent onboarding new teams to Airflow dramatically.

[dag-factory](https://github.com/ajbosco/dag-factory) is a brand new project, so if you try it and have any suggestions or issues [let me know](https://github.com/ajbosco/dag-factory/issues/new)! Similar tools include [boundary-layer](https://github.com/etsy/boundary-layer) from etsy and [airconditioner](https://github.com/wooga/airconditioner) (great name!) from wooga, so check them out too!
