$scriptPath = Split-Path $MyInvocation.InvocationName
Import-Module (join-path $scriptPath psake.psm1)
invoke-psake -framework '4.0'