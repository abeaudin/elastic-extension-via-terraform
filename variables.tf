variable "ec_api_key" {
  description = "Elastic Cloud API key. Generate one at https://cloud.elastic.co/account/keys"
  type        = string
  sensitive   = true
}

variable "ec_region" {
  description = "Elastic Cloud region, e.g. 'gcp-us-central1', 'aws-us-east-1', 'azure-eastus2'. Find valid values at https://cloud.elastic.co -> Create deployment -> region dropdown, or via the ec_stack data source."
  type        = string
}

variable "deployment_template_id" {
  description = "Deployment template id matching your chosen region/provider, e.g. 'gcp-general-purpose', 'aws-io-optimized-v2', 'azure-io-optimized-v3'. Find this by starting a deployment in the Cloud UI, clicking 'Equivalent API request' before creating, and copying the deployment_template_id field - or run: curl -s -H \"Authorization: ApiKey $EC_API_KEY\" https://api.elastic-cloud.com/api/v1/platform/configuration/templates/deployments?region=<ec_region>"
  type        = string
}

variable "elastic_stack_version" {
  description = "Elastic Stack version to deploy, e.g. '9.1.5'. Must be a version currently offered in your target region - check the Cloud UI version dropdown for valid values."
  type        = string
}

variable "deployment_name" {
  description = "Name for the test deployment"
  type        = string
  default     = "test"
}

variable "bundle_zip_path" {
  description = "Path to the zipped bundle file. Defaults to synonyms-bundle.zip - zip must contain a dictionaries/ folder at its root (e.g. dictionaries/synonyms.txt), per Elastic Cloud's custom bundle requirements."
  type        = string
  default     = "./synonyms-bundle.zip"
}
