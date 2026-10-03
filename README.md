# Elastic Cloud custom bundle extension test

A minimal, working Terraform project that proves out Elastic Cloud Hosted's
custom bundle/extension pipeline end to end: upload a file, attach it to a
deployment, confirm Elasticsearch can actually read it and use it.

The test case here is a synonyms dictionary (`synonyms.txt`) used by
Elasticsearch's core `synonym` token filter - deliberately chosen because
it requires **no plugin dependency**, unlike CJK word-breaker tokenizers
(Nori, Kuromoji, ICU) which need a separate official-plugin extension on
top of the bundle itself. See [Notes and gotchas](#notes-and-gotchas) below
if you do need to test a plugin-dependent tokenizer.

Works against AWS, GCP, or Azure - the provider/region/template are all
variables.

## What's in this repo

| File | Purpose |
|---|---|
| `main.tf` | Provider config, the bundle extension resource, the test deployment |
| `variables.tf` | All configurable inputs |
| `outputs.tf` | Deployment connection details after apply |
| `terraform.tfvars.example` | Template for your real values |
| `synonyms.txt` | The test dictionary file (create this yourself - see below) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.2.7
  ```bash
  brew install hashicorp/tap/terraform
  ```
- An Elastic Cloud account and API key: `cloud.elastic.co/account/keys`

## Setup

### 1. Configure your variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | What it is | Where to get it |
|---|---|---|
| `ec_api_key` | Elastic Cloud API key | `cloud.elastic.co/account/keys` -> Create API key |
| `ec_region` | Region slug | e.g. `gcp-us-central1`, `azure-eastus2`, `aws-us-east-1` - Cloud UI region dropdown |
| `deployment_template_id` | Template matching your region/provider | Start a deployment in the UI, click "Equivalent API request" *before* confirming, copy the field, then cancel. Or: `curl -s -H "Authorization: ApiKey $EC_API_KEY" "https://api.elastic-cloud.com/api/v1/platform/configuration/templates/deployments?region=<ec_region>"` |
| `elastic_stack_version` | Stack version, e.g. `9.1.5` | Cloud UI version dropdown |
| `deployment_name` | Any string | defaults to `test` |
| `bundle_zip_path` | Path to the zip from step 1 | defaults to `./synonyms-bundle.zip` |

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

Takes a couple of minutes. Note the outputs:
```bash
terraform output
terraform output -raw elasticsearch_password
```

### 3. Verify the bundle actually loaded

Log into Kibana (URL from `terraform output kibana_endpoint`, user `elastic`,
password from above), open Dev Tools, and run:

```
PUT synonym_sample
{
  "settings": {
    "index": {
      "analysis": {
        "filter": {
          "my_synonyms": {
            "type": "synonym",
            "synonyms_path": "synonyms.txt"
          }
        },
        "analyzer": {
          "my_analyzer": {
            "tokenizer": "standard",
            "filter": ["lowercase", "my_synonyms"]
          }
        }
      }
    }
  }
}
```

A `no_such_file_exception` here means the bundle didn't attach/extract -
see [Troubleshooting](#troubleshooting-checklist). Success means the file
is readable on the node.

Then confirm the synonyms are actually functioning, not just present:

```
POST synonym_sample/_analyze
{
  "analyzer": "my_analyzer",
  "text": "I bought a laptop"
}
```

You should see both `laptop` and `notebook computer` (type `SYNONYM`) in the
token list - proof the bundle is uploaded, attached, extracted, and actively
read by Elasticsearch.

### 4. Clean up

```bash
terraform destroy
```

