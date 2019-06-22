#
# PSake build script for Niche Commandline library
#
properties {
    $baseDir = resolve-path .\
    $buildDir = "$baseDir\build"
	$build_artifacts_dir = "$build_dir\artifacts\"
	$srcDir = resolve-path $baseDir
}

## ----------------------------------------------------------------------------------------------------
##   Targets 
## ----------------------------------------------------------------------------------------------------
## Top level targets used to run builds


Task Default -Depends Compile.Assembly

Task Integration.Build -Depends Clean, Debug.Build, Compile.Assembly, Unit.Tests

Task CI.Build -Depends Clean, Debug.Build, Compile.Assembly





Task Compile.Assembly -Depends Requires.BuildType, Requires.MSBuild, Requires.BuildDir {

    exec { & $msbuildExe /p:Configuration=$buildType ".\BuildScriptLabs.sln" /verbosity:minimal /fileLogger /flp:verbosity=detailed`;logfile=$buildDir\BuildScriptLabs.txt }
}




Task Clean {
    remove-item $buildDir -recurse -force -erroraction silentlycontinue
    
    if (!(test-path $buildDir)) { 
        $quiet = mkdir $buildDir 
    }   
}

Task Unit.Tests -Depends Requires.XUnitConsole, Configure.TestResultsFolder, Compile.Assembly {

	# Find all tests assemblies
	$testAssemblies = Get-ChildItem -Path $buildDir\*.Tests\$buildType\*.Tests.dll

	foreach($testAssembly in $testAssemblies){
		Write-Header $testAssembly.Name

		$xmlReportFile = [System.IO.Path]::ChangeExtension($testAssembly.Name, ".xunit.xml")
		$htmlReportFile = [System.IO.Path]::ChangeExtension($testAssembly.Name, ".xunit.html")
		$xmlReportPath = join-path $testResultsFolder $xmlReportFile
		$htmlReportPath = join-path $testResultsFolder $htmlReportFile

		Write-Host "Test Assembly Path: $testAssembly"
		Write-Host "Test XML Report Path: $xmlReportPath"
		Write-Host "Test HTML Report Path: $htmlReportPath"
		

		pushd $testProject.Directory.FullName
		exec { & $xunitExe $testAssembly -html $htmlReportPath -Xml $xmlReportPath }
		popd
	}
}


Task Release.Build {
    $script:buildType = "Release"
    Write-Host "Release build configured"
}

Task Debug.Build {
    $script:buildType = "Debug"
    Write-Host "Debug build configured"
}


Task Configure.TestResultsFolder -Depends Requires.BuildDir {

    $script:testResultsFolder = join-path $buildDir testing.results
    Write-Host "Test results folder: $testResultsFolder"

    if (test-path $testResultsFolder) {
        remove-item $testResultsFolder -recurse -force -erroraction silentlycontinue    
    }

    mkdir $testResultsFolder | Out-Null    
}


## ----------------------------------------------------------------------------------------------------
##   Requires 
##		Find tools required for Ci/CD pipeline
## ----------------------------------------------------------------------------------------------------



Task Requires.BuildDir {
    if (test-path $buildDir)
    {
        Write-Host "Build folder is: $buildDir"
    }
    else {
        Write-Host "Creating build folder $buildDir"
        mkdir $buildDir | out-null
    }
}

Task Requires.BuildType {
    
    if ($buildType -eq $null) {
        
        throw "No build type specified"
    }

    Write-Host "$buildType build confirmed"
}

Task Requires.MSBuild {

	# Select cmdlet to get first item in collection if there are more than one match 
    $script:msbuildExe = 
        resolve-path "C:\Program Files (x86)\Microsoft Visual Studio\*\*\MSBuild\*\Bin\MSBuild.exe" | Select -First 1

    if ($msbuildExe -eq $null)
    {
        throw "Failed to find MSBuild"
    }

    Write-Host "Found MSBuild here: $msbuildExe"
}

Task Requires.NuGet { 

    $script:nugetExe = (get-command nuget -ErrorAction SilentlyContinue).Source

    if ($nugetExe -eq $null) {
        $script:nugetExe = resolve-path ".\packages\NuGet.CommandLine.*\tools\nuget.exe" -ErrorAction SilentlyContinue
    }

    if ($nugetExe -eq $null)
    {
        throw "Failed to find nuget.exe"
    }

    Write-Host "Found Nuget here: $nugetExe"
}


Task Requires.XUnitConsole {

    $script:xunitExe =
        resolve-path ".\packages\xunit.runner.console.*\tools\net471\xunit.console.exe"

    if ($xunitExe -eq $null)
    {
        throw "Failed to find XUnit.Console.exe"
    }

    Write-Host "Found XUnit.Console here: $xunitExe"
}

## ----------------------------------------------------------------------------------------------------
##   Utility Methods
## ----------------------------------------------------------------------------------------------------

formatTaskName { 
    param($taskName) 

    $divider = "-" * 70
    return "`r`n$divider`r`n$taskName`r`n$divider"
}

function Write-Header($message) {
    $divider = "-" * ($message.Length + 4)
    Write-Output "`r`n$divider`r`n  $message`r`n$divider`r`n"
}