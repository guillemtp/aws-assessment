output "user_pool_id" {
  value = module.auth.user_pool_id
}

output "user_pool_client_id" {
  value = module.auth.user_pool_client_id
}

output "api_endpoints" {
  value = {
    (var.primary_region)   = module.stack_use1.api_endpoint
    (var.secondary_region) = module.stack_euw1.api_endpoint
  }
}
