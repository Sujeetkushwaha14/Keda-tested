provider "azurerm" {
    subscription_id = "6dbc33a2-5da4-4090-8ac2-b8dde7d2a834"
  features {}
}

locals {
  aks_name = "kedaclustersk"
  rg_name  = "Sujeetrg"
  location = "centralindia"
}

resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
}

# ---------------------------------------
# 1. Azure CNI + Private + Secure AKS
# ---------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "prodaks"

  sku_tier = "Standard"

  oidc_issuer_enabled = true
  workload_identity_enabled = true

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name                = "systempool"
    auto_scaling_enabled = true
    node_count          = 2
    vm_size             = "standard_a2_v2"
    min_count           = 2
    max_count           = 6
    type                = "VirtualMachineScaleSets"
    orchestrator_version = "1.29"
  }

  identity {
    type = "SystemAssigned"
  }

  azure_policy_enabled = true
  role_based_access_control_enabled = true

  tags = {
    env = "prod"
  }
}

# ---------------------------------------------------
resource "azurerm_storage_account" "keda_sa" {
  name                     = "kedastoragesujeet"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_queue" "keda_queue" {
  name                 = "keda-queue"
  storage_account_id = azurerm_storage_account.keda_sa.id
}


variable "tags" {
  type = map(string)
  default = {
    project = "keda-aks"
    env     = "prod"
  }
}


output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

