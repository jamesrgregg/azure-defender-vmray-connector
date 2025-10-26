@description('The Azure region into which the resources should be deployed.')
param location string = 'westus3'

@description('The environment for which the deployment is being executed')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Required. The name of the resource group to deploy')
param resourceGroupName string = 'rg-vmray-sec-${location}-${environment}'

@description('Required. The name of the function app to deploy')
param functionAppName string = 'func-vmray-${environment}'

@description('Required. The name of the storage account to deploy')
param storageAccountName string = take('stvmray${environment}${uniqueString(subscription().id)}', 24)

@description('Required. The name of the app service plan to deploy')
param appServicePlanName string = 'asp-vmray-${environment}'

@description('Required. The name of the app insights instance to deploy')
param appInsightsName string = 'appi-vmray-${environment}'

@description('Required. The name of the log analytics workspace to deploy')
param logAnalyticsName string = 'log-vmray-${environment}'

@description('Required. The name of the key vault to deploy')
param keyVaultName string = 'kv-vmray-${environment}'

// Create Resource Group
module rg 'br/public:avm/res/resources/resource-group:0.4.2' = {
  name: 'rg-deployment'
  scope: subscription()
  params: {
    name: resourceGroupName
    location: location
    tags: {
      Environment: environment
      Application: 'VMRay Defender'
    }
  }
}

// Create Key Vault
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: resourceGroup(resourceGroupName)
  name: 'kv-deployment'
  params: {
    name: keyVaultName
    location: location
    enableRbacAuthorization: true
    sku: 'standard'
  }
  dependsOn: [
    rg
  ]
}

// Create Log Analytics Workspace
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'log-analytics-deployment'
  params: {
    name: logAnalyticsName
    location: location
  }
  dependsOn: [
    rg
  ]
}

// Create Application Insights
module appInsights 'br/public:avm/res/insights/component:0.6.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'app-insights-deployment'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: logAnalytics.outputs.resourceId
    kind: 'web'
  }
}

// Create Storage Account
module storage 'br/public:avm/res/storage/storage-account:0.27.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'storage-deployment'
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    rg
  ]
}

// Create App Service Plan
module appServicePlan 'br/public:avm/res/web/serverfarm:0.5.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'app-service-plan-deployment'
  params: {
    name: appServicePlanName
    location: location
    skuName: 'Y1'
    kind: 'functionapp'
  }
  dependsOn: [
    rg
  ]
}

// Create Function App
module functionApp 'br/public:avm/res/web/site:0.19.3' = {
  scope: resourceGroup(resourceGroupName)
  name: 'function-app-deployment'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    siteConfig: {
      pythonVersion: '3.9'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.outputs.instrumentationKey
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storage.outputs.name}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storage.outputs.name}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
      ]
    }
  }
}

// Outputs
output functionAppResourceId string = functionApp.outputs.resourceId
output keyVaultResourceId string = keyVault.outputs.resourceId
output storageAccountResourceId string = storage.outputs.resourceId
