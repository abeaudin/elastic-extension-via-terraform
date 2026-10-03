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

### 1. Create the test dictionary file and zip it

```bash
cat > synonyms.txt << 'EOF'
usa, united states, united states of america
laptop, notebook computer
EOF

zip synonyms-bundle.zip synonyms.txt
```

(Elastic's docs say dictionaries should sit in a `dictionaries/` folder
inside the zip - in testing this made no difference either way, see
[the gotcha below](#the-dictionaries-folder-in-the-zip-doesnt-matter).
Either structure works.)

### 2. Configure your variables

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

### 3. Deploy

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

### 4. Verify the bundle actually loaded

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

### 5. Clean up

```bash
terraform destroy
```

## Notes and gotchas

A handful of things we hit building this that aren't obvious from the docs:

#### Provider schema uses attribute syntax throughout
Newer `elastic/ec` provider versions (`~> 0.13` here) use `elasticsearch = {...}`
attribute syntax, not the older `elasticsearch {...}` block syntax - and that
consistency has to hold all the way down into nested fields like `extension`
and `hot`. Mixing the two styles produces a `Missing key/value separator`
parse error.

#### `elasticsearch.hot` requires an (even empty) `autoscaling` attribute
```hcl
hot = {
  size        = "1g"
  zone_count  = 1
  autoscaling = {}
}
```
Omitting it entirely fails plan-time validation with `attribute "autoscaling"
is required`.

#### The `extension` block needs `url`, not just `extension_id`
```hcl
extension = [
  {
    name         = ec_deployment_extension.synonyms.name
    type         = "bundle"
    version      = ec_deployment_extension.synonyms.version
    extension_id = ec_deployment_extension.synonyms.id
    url          = ec_deployment_extension.synonyms.url
  }
]
```

#### Provider auth attribute is `apikey`, not `api_key`
```hcl
provider "ec" {
  apikey = var.ec_api_key
}
```

#### CJK tokenizers (Nori, ICU, Kuromoji) need a *second* extension
Official Elastic-provided analysis plugins aren't bundled by default on
Elastic Cloud - they're enabled the same way as a custom plugin upload, just
without a file:
```hcl
resource "ec_deployment_extension" "nori_plugin" {
  name           = "analysis-nori"
  description    = "Official Nori analysis plugin"
  version        = var.elastic_stack_version
  extension_type = "plugin"
}
```
This then needs its own entry in the `extension` list alongside any custom
bundle. If you just want to prove the *bundle* pipeline works without this
extra complexity, use a core-Elasticsearch feature like the synonym filter
(as this repo does) instead.

#### The `dictionaries/` folder in the zip doesn't matter
Elastic's docs say dictionaries should be placed in a `/dictionaries` folder
inside the zip. In testing, this didn't affect the outcome either way - the
bundle gets extracted flat into `/app/config/`, and `synonyms_path` just
takes the bare filename (`synonyms.txt`) regardless of whether the zip had a
`dictionaries/` subfolder or not.

#### Deleting an in-use extension fails if done in the same apply as unattaching it
If you remove or rename an extension resource in your `.tf` files while it's
still attached to a deployment, Terraform can try to delete it before
updating the deployment to stop referencing it, and the API rejects it:
```
extensions.extension_in_use: Cannot delete extension [...]. It is used by
deployments [...].
```
Fix: apply the deployment change first with `-target`, then apply again for
the cleanup:
```bash
terraform apply -target=ec_deployment.test
terraform apply
```
Simplest overall fix if you're changing names/extensions significantly:
`terraform destroy` and re-apply fresh.

## Troubleshooting checklist

If a `_analyze` or `PUT` test fails with a file-not-found error:

1. **Confirm the bundle is in the live plan** (not just Terraform state):
   ```bash
   curl -s -H "Authorization: ApiKey $EC_API_KEY" \
     "https://api.elastic-cloud.com/api/v1/deployments/<DEPLOYMENT_ID>" \
     | jq '.resources.elasticsearch[0].info.plan_info.current.plan.elasticsearch'
   ```
   Should list your bundle under `user_bundles` with a matching
   `elasticsearch_version`.

2. **Confirm the plan actually finished applying** (not mid-rollout):
   ```bash
   curl -s -H "Authorization: ApiKey $EC_API_KEY" \
     "https://api.elastic-cloud.com/api/v1/deployments/<DEPLOYMENT_ID>" \
     | jq '.resources.elasticsearch[0].info.plan_info.current | {healthy, attempt_start_time, attempt_end_time}'
   ```

3. **Updating a bundle's file content alone doesn't restart nodes.** Per
   Elastic's docs, bundle/plugin files are downloaded and made available
   only when a node is started. Changing `synonyms.txt` and re-running
   `terraform apply` won't necessarily trigger a restart if the extension's
   name/version/id didn't change. Force one via the Cloud UI deployment
   actions menu, the restart API endpoint, or a trivial `.tf` change that
   forces a real plan diff on the deployment resource.
