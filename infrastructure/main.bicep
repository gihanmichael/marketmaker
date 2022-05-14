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
