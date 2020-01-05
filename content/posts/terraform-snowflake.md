+++ 
date = "2020-01-05"
title = "Terraforming Snowflake"
slug = "terraform-snowflake" 
description = "manage Snowflake objects with Terraform"
+++

![Snowflake + Terraform](/images/terraform_snowflake.png)

## What is Snowflake?

[Snowflake](https://www.snowflake.com/) is a managed cloud data warehouse solution. It is similar to BigQuery or Redshift, but has some unique features like separation of compute and storage and strong support for semi-structured data (JSON, Parquet, Avro) that differentiate it.

## What is Terraform?

[Terraform](https://www.terraform.io/) is a tool from Hashicorp for managing infrastructure via code. You can use it to provision, update, or delete a wide range of resources like [EC2 instances](https://www.terraform.io/docs/providers/aws/r/instance.html), 
[Datadog monitors](https://www.terraform.io/docs/providers/datadog/r/monitor.html), 
[OpsGenie schedules](https://www.terraform.io/docs/providers/opsgenie/r/schedule.html) and more. This allows you to know the current state of your infrastructure at any given time and to control how it is updated. Terraform ships with many [providers](https://www.terraform.io/docs/providers/index.html). Unfortunately, Snowflake is not one of them! However, it also supports [third-party providers](https://www.terraform.io/docs/plugins/basics.html), which means users can write their own providers for almost any service. As an example (and shameless plug), check out [this one](https://github.com/ajbosco/terraform-provider-segment) I wrote for [Segment](https://segment.com/)'s API. 

## Why use Terraform with Snowflake?

As luck would have it, the [Chan Zuckerberg Initiative](https://chanzuckerberg.com/) has done the hard work for us and open-sourced a [Snowflake Terraform Provider](https://github.com/chanzuckerberg/terraform-provider-snowflake) that we can use
to manage many Snowflake objects like roles, grants, and users. Therefore, by using Terraform with Snowflake, we can always know the current state of our Snowflake environments. Like which schemas exists, the size of a warehouse, and maybe most importantly, which users have access to which Snowflake objects. With this setup we can avoid situations where someone *accidentally* manually grants a user the wrong role with too much access or spins up a 4X-Large Warehouse that never [auto-suspends](https://docs.snowflake.net/manuals/user-guide/warehouses-overview.html#auto-suspension-and-auto-resumption).

If this all sounds great, then let's walk through an example using Terraform to setup roles, users, schemas, and grant access in Snowflake.

## Setting up Terraform

Before we get started, you'll need to install Terraform. I'd recommend following the [official documentation](https://learn.hashicorp.com/terraform/getting-started/install.html) for this. I'll be using Terraform 0.12 in the examples below. I'd also suggest setting up a [Remote State](https://www.terraform.io/docs/state/remote.html) to make it easier for a team to manage your resources, but that's not needed to get started. A Remote State writes your Terraform state to a remote data store like AWS S3 that all team members can access versus using local storage for the state.

After you have Terraform setup, you'll need to download the Snowflake Terraform Provider from the latest [releases](https://github.com/chanzuckerberg/terraform-provider-snowflake/releases) and move it to the appropriate directory (usually `~/.terraform.d/plugins`). Next follow the steps in the provider [README](https://github.com/chanzuckerberg/terraform-provider-snowflake#authentication) for the authentication method of your choosing and create a file called `main.tf` that looks something like this:

```hcl
provider "snowflake" {
  account = "your-snowflake-account"
  region  = "your-snowflake-region"
}
```

After that run `terraform init` and you should see the following meaning we're ready to go:

```
Initializing the backend...

Initializing provider plugins...

Terraform has been successfully initialized! 
```

## Terraforming Schemas

First, we'll create two databases in Snowflake. Create a file called `schemas.tf` that looks like this:

```hcl
locals {
  schemas = {
    "RAW" = {
      database = "DEV"
      comment = "contains raw data from our source systems"
    }
    "ANALYTICS" = {
      database = "DEV"
      comment = "contains tables and views accessible to analysts and reporting"
    }
  }
}

resource "snowflake_schema" "schema" {
  for_each = local.schemas
  name     = each.key
  database = each.value.database
  comment  = each.value.comment
}
```

Note, we're taking advantage of the new loops in Terraform 0.12 to avoid copying and pasting the `snowflake_role` resource every time we add a new role. Then run `terraform plan` to see what resources will be created. This command should return saying 2 new schemas would be created in Snowflake. If things look good, run `terraform apply` to create them.

## Terraforming Roles

Next, let's create two [Snowflake roles](https://docs.snowflake.net/manuals/sql-reference/sql/create-role.html) with Terraform. As an aside, dbt has a great [blog post](https://blog.getdbt.com/how-we-configure-snowflake/) on how they structure roles for their clients that I recommend reading. The example here sort of copies this structure.

Create a file `roles.tf` that looks like this:

```hcl
locals {
  roles = {
    "LOADER" = {
      comment = "Owns the tables in raw schema"
    }
    "TRANSFORMER" = {
      comment = "Has query permissions on tables in raw schema and owns tables in the analytics schema."
    }
  }
}

resource "snowflake_role" "role" {
  for_each = local.roles
  name     = each.key
  comment  = each.value.comment
}
```

As before, run `terraform plan` to see what resources will be created. This command should return saying 2 new roles would be created in Snowflake. If things look good, run `terraform apply` to create them.

Roles are great, but they're even better if you can do something with them, so let's change our `schemas.tf` file to look like this: 

```hcl
locals {
  schemas = {
    "RAW" = {
      database = "DEV"
      comment = "contains raw data from our source systems"
      usage_roles = ["TRANSFORMER"]
      all_roles = ["LOADER"]
    }
    "ANALYTICS" = {
      database = "DEV"
      comment = "contains tables and views accessible to analysts and reporting"
      usage_roles = []
      all_roles = ["TRANSFORMER"]
    }
  }
}

resource "snowflake_schema" "schema" {
  for_each = local.schemas
  name     = each.key
  database = each.value.database
  comment  = each.value.comment
}

resource "snowflake_schema_grant" "schema_grant_usage" {
  for_each      = local.schemas
  schema_name   = each.key
  database_name = each.value.database
  privilege     = "USAGE"
  roles         = each.value.usage_roles
  shares        = []
}

resource "snowflake_schema_grant" "schema_grant_all" {
  for_each      = local.schemas
  schema_name   = each.key
  database_name = each.value.database
  privilege     = "ALL"
  roles         = each.value.all_roles
  shares        = []
}
```

A quick `terraform plan` should show that we are ready to grant the appropriate access on each of our schemas to each of our roles. If things look good, run `terraform apply` to create the grants in Snowflake.

## Terraforming Users

Now that we have roles, let's make some users for those roles. Create a file called `users.tf` like this:

```hcl
locals {
  users = {
    "MAC" = {
      login_name = "MAC_DATAENGINEER@MACANDCHEESE.COM"
      role       = "TRANSFORMER"
      namespace  = "DEV.PUBLIC"
      warehouse  = "TRANSFORMER_WH"
    }
    "CHEESE" = {
      login_name = "CHEESE_DATAENGINEER@MACANDCHEESE.COM"
      role       = "TRANSFORMER"
      namespace  = "DEV.PUBLIC"
      warehouse  = "TRANSFORMER_WH"
    }
    "STITCH" = {
      login_name = "STITCH@MACANDCHEESE.COM"
      role       = "LOADER"
      namespace  = "DEV.PUBLIC"
      warehouse  = "LOADER_WH"
    }
  }
}

resource "snowflake_user" "user" {
  for_each             = local.users
  name                 = each.key
  login_name           = each.value.login_name
  default_role         = each.value.role
  default_namespace    = each.value.namespace
  default_warehouse    = each.value.warehouse
  must_change_password = false
}
```

Again, run `terraform plan` to see what resources will be created. This command should return saying 3 new users would be created in Snowflake (note, we also are assuming that passwords do not need to be changed because we've setup SSO before we started this). If things look good, run `terraform apply` to create them.

But wait, we've given these users a `default_role`, but that role hasn't been granted to them yet! A user that has not been granted their default role won't be able to do anything in Snowflake. Let's fix that by modifying the `roles.tf` file so that it looks like this:

```hcl
locals {
  roles = {
    "LOADER" = {
      comment = "Owns the tables in raw schema"
      users = ["STITCH"]
    }
    "TRANSFORMER" = {
      comment = "Has query permissions on tables in raw schema and owns tables in the analytics schema."
      users = ["MAC", "CHEESE"]
    }
  }
}

resource "snowflake_role" "role" {
  for_each = local.roles
  name     = each.key
  comment  = each.value.comment
}

resource "snowflake_role_grants" "role_grant" {
  for_each  = local.roles
  role_name = each.key
  users     = each.value.users
  roles     = []
}
```

Yet again, we'll run `terraform plan` to see the changes, which should be that we will now be granting the appropriate roles to our users. If that's what the output says, run `terraform apply` to make it so in Snowflake.

And that's it! We now have roles, schemas, and users created in Snowflake and managed by Terraform. Time to commit these files and put a PR into GitHub! As a next step, check out [Atlantis](https://www.runatlantis.io/) to manage Terraform through Pull Requests or [Terraform Cloud](https://www.terraform.io/docs/cloud/index.html) to make it easier for teams work with Terraform.