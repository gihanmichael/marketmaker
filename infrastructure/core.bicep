param location string
param prefix string
param vnetSettings object = {
  addressPrefixes:[
    '10.0.0.0/19'
  ]
  subnets:[
    //You can create more subnets by copying the following snippets
    {
      name: 'subnet1'
      addressPrefix:'10.0.0.0/21'
    }
    //additional subnets are required for ACS, namely the app and control plane.
    //You can use the visual subnet calculator www.davidc.net
    {
      name: 'acaAppSubnet'
      addressPrefix:'10.0.8.0/21'
    }
    {
      name: 'acaControlPlaneSubnet'
      addressPrefix:'10.0.16.0/22'
    }
  ]
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: '${prefix}-default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allowhttpsinbound'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          description: 'Allow Https Traffic Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          priority: 200



        }
      }

    ]
  }
}



resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetSettings.addressPrefixes
      
    }
    subnets: [for subnet in vnetSettings.subnets:{
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        networkSecurityGroup: {
          id: networkSecurityGroup.id
        }
        //Private Endpoint cannot be created with NSG's its still in preview so it needs to be disabled right now
        privateEndpointNetworkPolicies: 'disabled'
      }
    }]
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-03-15' = {
  name: '${prefix}-cosmos-account'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-06-15' = {
  name: '${prefix}-sqldb'
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: '${prefix}-sqldb'
    }
    options: {

    }
  }
}

//the orders Table in the database
resource sqlContainerName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-06-15' = {
  parent: sqlDb 
  name: '${prefix}-orders'
  properties: {
    resource: {
      id: '${prefix}-orders'
      partitionKey: {
        paths: [
          '/id'
        ]
 
      }
    }
    options: {}
  }
}

//Dapper needs another continer with a partitionkey so we will deploy another key
resource stateCOntainerName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-06-15' = {
  parent: sqlDb
  name: '${prefix}-state'
  properties: {
    resource: {
      id: '${prefix}-state'
      partitionKey: {
        paths: [
          '/partitionKey'
        ]
      }
    }
    options: {}
  }
}


//Private DNS, Actual DNS, Link to the DNS and link to private endpoint.
resource cosmosPrivateDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  //You can look these up in the Microsoft Docs for cosmos its the one used below
  name: 'privatelink.documents.azure.com'
  location: 'global' //location has to be Global here or it will throw an error.
}

//Linking your Private DNS Zone to your Virtual Network
resource cosmosPrivateDnsNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${prefix}-cosmos-dns-link'
  location:'global'
  parent: cosmosPrivateDns
  properties:{
    registrationEnabled:false
    virtualNetwork: {
      id:virtualNetwork.id
    }
  }
}

//Add the actual Private Endpoint itself

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: '${prefix}-cosmos-pe'
  location: location
  properties: {
  privateLinkServiceConnections:[
    {
      name:'${prefix}-cosmos-pe'
      properties: {
        privateLinkServiceId: cosmosDbAccount.id
        groupIds: [
          'SQL'
        ]
      }
    }
  ]  
  //The subnet the PrivateEndpoint is going to be linked to in the network, we are going to put it in the first subnet but if we wanted to pick the subnet we could. We will have to turn into a parameter
  subnet: {
   id: virtualNetwork.properties.subnets[0].id 
  }
  }

}


//Link the DNS Zone to the Private Endpoint, you make use of the private DNS Zone groups
resource cosmosPrivateEndpointDnsLink  'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-08-01' = {
  name: '${prefix}-cosmos-pe-dns'
  parent: cosmosPrivateEndpoint
  properties: {
   privateDnsZoneConfigs: [
    { //name can be whatever you want, the below is set to be easily identifiable
      name: 'privatelink.documents.azure.com'
      properties: {
        //ID of the DNS Zone you want to Link
        privateDnsZoneId:cosmosPrivateDns.id
        }
    }
  ] 
      
 }
}

//we need a container registry where the developers can push their images in to
//container apps don't support managed identity, so using key vault to make it more secure

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  //if you need to change the naming on the fly such as taking hyphen out
  name: '${replace(prefix,'-','')}acr'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

//key vault api is old so change it to the new API 2021-10-01 from  2019-09-01
resource keyVault 'Microsoft.KeyVault/vaults@2021-10-01' = {
  name: 'name'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true //this is really important
    enabledForDiskEncryption: true
    // the following parameter is available in the new api only
    enableRbacAuthorization: true
    tenantId: tenant().tenantId
    accessPolicies: [
      {
        tenantId: 'tenantId'
        objectId: 'objectId'
        permissions: {
          keys: [
            'get'
          ]
          secrets: [
            'list'
            'get'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}


//Create a key vault secret
resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${keyVault.name}/acrAdminPassword'
  properties: {
    value: containerRegistry.listCredentials().passwords[0].value
  }
}

