output "elasticsearch_endpoint" {
  value = ec_deployment.test.elasticsearch.https_endpoint
}

output "kibana_endpoint" {
  value = ec_deployment.test.kibana.https_endpoint
}

output "elasticsearch_username" {
  value = ec_deployment.test.elasticsearch_username
}

output "elasticsearch_password" {
  value     = ec_deployment.test.elasticsearch_password
  sensitive = true
}

output "extension_id" {
  value = ec_deployment_extension.synonyms.id
}
