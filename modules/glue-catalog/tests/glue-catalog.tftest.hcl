mock_provider "aws" {}

variables {
  databases = {
    raw = {}
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "single_database_with_defaults" {
  command = plan

  assert {
    condition     = length(aws_glue_catalog_database.this) == 1 && aws_glue_catalog_database.this["raw"].name == "raw"
    error_message = "One database named after its key must be planned"
  }

  assert {
    condition     = aws_glue_catalog_database.this["raw"].description == null
    error_message = "description must be unset when not given"
  }

  assert {
    condition     = aws_glue_catalog_database.this["raw"].tags["Name"] == "raw"
    error_message = "Name must be added to the database tags"
  }
}

run "several_databases" {
  command = plan

  variables {
    databases = {
      raw     = { description = "Raw zone", location_uri = "s3://alpha-dev-raw/raw/" }
      curated = { description = "Curated zone" }
      sandbox = {}
    }
    tags = { Project = "alpha" }
  }

  assert {
    condition     = toset(keys(aws_glue_catalog_database.this)) == toset(["raw", "curated", "sandbox"])
    error_message = "Every key of databases must become a database"
  }

  assert {
    condition     = aws_glue_catalog_database.this["raw"].description == "Raw zone" && aws_glue_catalog_database.this["raw"].location_uri == "s3://alpha-dev-raw/raw/"
    error_message = "description and location_uri must be passed through"
  }

  assert {
    condition     = aws_glue_catalog_database.this["curated"].description == "Curated zone"
    error_message = "description must be passed through when location_uri is not given"
  }

  assert {
    condition     = aws_glue_catalog_database.this["curated"].tags["Project"] == "alpha" && aws_glue_catalog_database.this["curated"].tags["Name"] == "curated"
    error_message = "Given tags must be merged with Name"
  }
}

run "name_boundaries_are_accepted" {
  command = plan

  variables {
    databases = {
      a                                       = {}
      "9_lake"                                = {}
      (join("", [for i in range(255) : "a"])) = {}
    }
  }

  assert {
    condition     = length(aws_glue_catalog_database.this) == 3
    error_message = "1 and 255 character names, and names starting with a digit, are valid"
  }
}

run "no_databases_creates_nothing" {
  command = plan

  variables {
    databases = {}
  }

  assert {
    condition     = length(aws_glue_catalog_database.this) == 0 && length(output.database_names) == 0
    error_message = "An empty databases map must create no resources"
  }
}

run "outputs" {
  command = plan

  variables {
    databases = {
      raw     = {}
      curated = {}
    }
  }

  assert {
    condition     = join(",", output.database_names) == "curated,raw"
    error_message = "database_names must be the sorted database names"
  }

  assert {
    condition     = length(output.database_arns) == 2
    error_message = "database_arns must have one entry per database"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "uppercase_name_rejected" {
  command = plan

  variables {
    databases = { Raw = {} }
  }

  expect_failures = [var.databases]
}

run "hyphen_in_name_rejected" {
  command = plan

  variables {
    databases = { "alpha-raw" = {} }
  }

  expect_failures = [var.databases]
}

run "empty_name_rejected" {
  command = plan

  variables {
    databases = { "" = {} }
  }

  expect_failures = [var.databases]
}

run "name_over_255_chars_rejected" {
  command = plan

  variables {
    databases = { (join("", [for i in range(256) : "a"])) = {} }
  }

  expect_failures = [var.databases]
}

run "location_uri_not_s3_rejected" {
  command = plan

  variables {
    databases = { raw = { location_uri = "https://example.com/raw/" } }
  }

  expect_failures = [var.databases]
}
