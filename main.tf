terraform {
  required_version = ">= 1.2.7"

  required_providers {
    ec = {
      source  = "elastic/ec"
      version = "~> 0.13"
    }
  }
}

provider "ec" {
  apikey = var.ec_api_key
}

# Upload the zipped synonyms file as a bundle extension.
# This is core Elasticsearch functionality (the "synonym" token filter) -
# no plugin dependency at all, unlike Nori/ICU/Kuromoji. This makes the
# bundle available in your account's extension library, but does NOT yet
# attach it to any deployment - that happens in the ec_deployment resource below.
resource "ec_deployment_extension" "synonyms" {
  name           = "synonyms-test"
  description    = "Test word-grouping bundle, no plugin dependency"
  version        = var.elastic_stack_version
  extension_type = "bundle"
  file_path      = var.bundle_zip_path
  file_hash      = filebase64sha256(var.bundle_zip_path)
}

# Create a minimal test deployment and attach the bundle to it.
# This is a throwaway deployment for testing the extension pipeline end to end -
# resize or remove the kibana block if you don't need the UI.
resource "ec_deployment" "test" {
  name                   = var.deployment_name
  region                 = var.ec_region
  version                = var.elastic_stack_version
  deployment_template_id = var.deployment_template_id

  elasticsearch = {
    hot = {
      size        = "1g"
      zone_count  = 1
      autoscaling = {}
    }

    extension = [
      {
        name         = ec_deployment_extension.synonyms.name
        type         = "bundle"
        version      = ec_deployment_extension.synonyms.version
        extension_id = ec_deployment_extension.synonyms.id
        url          = ec_deployment_extension.synonyms.url
      }
    ]
  }

  kibana = {
    size       = "1g"
    zone_count = 1
  }
}
