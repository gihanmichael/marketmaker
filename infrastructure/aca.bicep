param location string
param prefix string
param vNetId string
//we can pass in the subnet id but to make things simple we are passing the vNet ID


param containerRegistryName string
param containerRegistryUsername string

@secure()
param containerRegistryPassword string
param containerVersion string
param cosmosAccountName string
param cosmosDbName string
param cosmosContainerName string




//deploy the Log Analytics wrokspace, to store the logs from the conatiner
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: '${prefix}-la-workspace'
  location: location
  properties: {
    sku: {
      name: 'Standard' //don't use the free one for other than dev test environments
    }
  }
}

//creating the container app in the environment, all these parameters can be found out from the arm/bicep spec page
//Might get changed from Microsoft.Web to Microsoft.App
resource env 'Microsoft.Web/kubeEnvironments@2021-03-01' = {
  name: '${prefix}-container-env'
  location: location
  kind: 'containerenvironment'
  properties: {
    environmentType:'managed' //this says we are using aca
    internalLoadBalancerEnabled:false
    appLogsConfiguration: {
        destination:'log-analytics'
        logAnalyticsConfiguration:{
          customerId:logAnalyticsWorkspace.properties.customerId
          sharedKey: logAnalyticsWorkspace.listkeys().primarySharedKey
        }

    }
    containerAppsConfiguration: {
      appSubnetResourceId: '${vNetId}/subnets/acaAppSubnet'
      controlPlaneSubnetResourceId: '${vNetId}/subnets/acaControlPlaneSubnet'

    }
  }
}

//we are going to need a key from the cosmosDB database..we can pass it as a parameter, but following is the way to grab it from an existing resource

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2022-02-15-preview' existing = {
  name: cosmosAccountName
  //this assumes its in the same resource group if not you can use the scope property
}
//this doesnt have to be created by bicep can be by a manually created resource.
var cosmosDbKey = cosmosDbAccount.listKeys().primaryMasterKey


//we need to deploy the container. Microsoft.Web, will soon be changed to Microsoft.App
resource apiApp 'Microsoft.Web/containerApps@2021-03-01' = {
  name: '${prefix}-api-container'
  location: location
  kind: 'containerapp'
  properties: {
    kubeEnvironmentId:env.id
    configuration: {
      secrets: [
        {
        name: 'container-registry-password'
        value: containerRegistryPassword
        }
      ]
      registries: [
        {
          server: '${containerRegistryName}azurecr.io'
          username: containerRegistryUsername
          passwordSecretRef: 'container-registry-password'
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
      }
    }
    template: {
      containers: [
        {
        image: '${containerRegistryName}.azurecr.io/hellok8s-node:${containerVersion}'
        name: 'lambdaapi' //needs to be lower case, can call it whatever you want
        resources: {
          cpu: '0.5'
          memory: '1Gi'
        }
      }
      ]
      //how many containers we need
      scale: {
        minReplicas: 1

      }
      //configuration for Dapr
      dapr: {
        enabled: true
        appPort: 3000
        appId: 'lambdaapi' //should be unique
        components: [
          {
            name: 'statestore'
            type: 'state.azure.cosmosdb'
            version: 'v1'
            metadata: [ //Square braces is array
              
              {
                name: 'url'
                value: 'https://{$cosmosAccountName}.documents.azure.com:443/' //you probably don't need the 443 at the end
              }
              {
                name: 'database'
                value: cosmosDbName
              }
              {
                name: 'collection'
                value: cosmosContainerName
              }
              {
                name: 'masterKey'
                value: cosmosDbKey
              }
            ]
          }
        ]
      }
    }
  }
}
