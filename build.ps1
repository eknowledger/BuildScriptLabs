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





Task Compile.Assembly -Depends Requires.BuildType, Requires.MSBuild, Requires.BuildDir, GenerateVersionInfo {

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




Task GenerateVersion {
	$tag = exec{ & git describe --exact-match --abbrev=0} | Out-String

	if ([string]::IsNullOrEmpty($tag))
    {
		Write-Host "No Tag Found, using default value"
      $result = "1.0.0"
    }
	
	$tag = $tag -replace "`n","" -replace "`r",""

	$script:version = $tag
	
	# Get current branch
	$branch = @{ $true = $env:APPVEYOR_REPO_BRANCH; $false = $(git symbolic-ref --short -q HEAD) }[$env:APPVEYOR_REPO_BRANCH -ne $NULL];
	# get total number of commit on the current branch
	$localRevision = $(git rev-list --count $branch)
	
	#get last commit hash on the branch
	$commitHash = $(git rev-parse --short $branch)

	# compute revision number for assemblies
	$revision = @{ $true = "{0:00000}" -f [convert]::ToInt32("0" + $env:APPVEYOR_BUILD_NUMBER, 10); $false = $localRevision }[$env:APPVEYOR_BUILD_NUMBER -ne $NULL];

	# get version friendly name of Branch
	$branchShort = "$($branch.Substring(0, [math]::Min(10,$branch.Length)))"

	$suffix = @{ $true = "ci-$branchShort-$commitHash"; $false = "local-$branchShort-$commitHash"}[$env:APPVEYOR_BUILD_NUMBER -ne $NULL]

	$script:patchVersion = $revision 
	$script:suffixVersion = $suffix


	echo "Branch: $branch"
	echo "Version: $tag"
	echo "Revision: $revision"
	echo "Suffix: $suffix" 
}


# Generate a VersionInfo.cs file for this build
Task GenerateVersionInfo -Depends GenerateVersion {
    foreach($assemblyInfo in (get-childitem $srcDir\AssemblyInfo.cs -recurse)) {
        $versionInfo = Join-Path $assemblyInfo.Directory "VersionInfo.cs"
        set-content $versionInfo -encoding UTF8 `
            "// Generated file - do not modify",
            "using System.Reflection;",
            "[assembly: AssemblyVersion(`"$version`")]",
            "[assembly: AssemblyFileVersion(`"$version.$patchVersion`")]",
            "[assembly: AssemblyInformationalVersion(`"$version.$patchVersion.$suffixVersion`")]"
        Write-Host "Generated $versionInfo"
    }
}


