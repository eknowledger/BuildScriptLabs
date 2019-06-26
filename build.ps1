# ====================================================================================================
# PSake build script
# Author: Ahmed Elmalt
# Inspired by: https://github.com/theunrepentantgeek/Niche.CommandLineProcessor/blob/master/build.ps1
#			   https://github.com/psake/psake/blob/master/build.ps1
# ====================================================================================================
properties {
    $baseDir = resolve-path .\
    $buildDir = "$baseDir\build"
	$srcDir = resolve-path $baseDir
	$solutionFile ="BuildScriptLabs"
	$solutionFilePath ="$baseDir\$solutionFile.sln"
}

## ----------------------------------------------------------------------------------------------------
##   Target Tasks 
##	 Top level targets used to run builds
## ----------------------------------------------------------------------------------------------------

Task Default -Depends BuildType-Debug, Compile

Task Debug -Depends BuildType-Debug, Clean, Restore, Compile, Test

Task Release -Depends BuildType-Release, Clean, Restore, Compile, Test, Pack

## ----------------------------------------------------------------------------------------------------
##   Core Tasks 
## ----------------------------------------------------------------------------------------------------

Task Restore -Depends LocateNuGet{
	$nugetPackagesDir = "$baseDir\packages"
	if (test-path $buildDir) { echo "Locating: $nugetPackagesDir" }

	echo "Removing: $nugetPackagesDir"
    remove-item $nugetPackagesDir -recurse -force -erroraction silentlycontinue
	
	echo "Restoring nuget pacakges to $nugetPackagesDir"
	exec{& $nugetExe restore $solutionFilePath}
}

Task Compile -Depends Init, GenerateVersionInfo {

	foreach($projFile in (Get-ChildItem -Path $srcDir\*.csproj -recurse)){
		$Name = [io.path]::GetFileNameWithoutExtension($projFile.Name)
		Write-Header $Name
		echo $projFile

		# Set build log file location
		$buildLogFile = "$buildDir\$Name.$buildType.log"

		# set build output Dir
		$outputDir = "$buildDir\$Name\$buildType"
		echo $outputDir

		exec { & $msbuildExe /p:Configuration=$buildType /p:OutputPath=$outputDir $projFile /verbosity:minimal /fileLogger /flp:verbosity=detailed`;logfile=$buildLogFile }
	}
}

Task Test -Depends Compile {

	# Find all tests assemblies
	$testAssemblies = Get-ChildItem -Path $buildDir\*.Tests\$buildType\*.Tests.dll

	foreach($testAssembly in $testAssemblies){
		Write-Header $testAssembly.Name

		$xmlReportFile = [System.IO.Path]::ChangeExtension($testAssembly.Name, ".xunit.xml")
		$htmlReportFile = [System.IO.Path]::ChangeExtension($testAssembly.Name, ".xunit.html")
		$xmlReportPath = join-path $buildDir $xmlReportFile
		$htmlReportPath = join-path $buildDir $htmlReportFile

		Write-Host "Test Assembly Path: $testAssembly"
		Write-Host "Test XML Report Path: $xmlReportPath"
		Write-Host "Test HTML Report Path: $htmlReportPath"
		

		pushd $testProject.Directory.FullName
		exec { & $xunitExe $testAssembly -html $htmlReportPath -Xml $xmlReportPath }
		popd
	}
}

Task Pack -Depends Compile{

	foreach($nuspecFile in (Get-ChildItem -Path $srcDir\*.nuspec -recurse)){
		echo "$nuspecFile"
		$Name = $nuspecFile.Name
		Write-Header $Name

		$packageVersion = "$version.$patchVersion"
		$projectFile = [System.IO.Path]::ChangeExtension($nuspecFile, ".csproj")
		echo $projectFile

		exec{
			 & $nugetExe pack $projectFile -version $packageVersion -outputdirectory $packagesFolder -basePath $buildDir -Suffix $suffixVersion -Build -IncludeReferencedProjects -properties Configuration=$buildType
		}
	}
}

## ----------------------------------------------------------------------------------------------------
##   Supporting Tasks 
##		Find tools required for Ci/CD pipeline
## ----------------------------------------------------------------------------------------------------

Task Init -Depends InitBuildDir, InitPackagesDir, ConfirmBuildType, LocateMSBuild, LocateXUnitConsole, LocateNuGet

Task Clean {

	if (test-path $buildDir) { echo "Locating: $buildDir" }

	echo "Removing: $buildDir"
    remove-item $buildDir -recurse -force -erroraction silentlycontinue
    
    if (!(test-path $buildDir)) { 
		echo "Creating: $buildDir"
        $quiet = mkdir $buildDir 
    }   
}

Task BuildType-Release {
    $script:buildType = "Release"
    echo "Build Type = Release"
}

Task BuildType-Debug {
    $script:buildType = "Debug"
    echo "Build Type = Debug"
}

Task InitBuildDir {
    if (test-path $buildDir){
        echo "Build folder is: $buildDir"
    }
    else {
        echo "Creating build folder $buildDir"
        mkdir $buildDir | out-null
    }
}

Task InitPackagesDir -Depends InitBuildDir {

    $script:packagesFolder = join-path $buildDir Packages
    echo "Package Dir: $packagesFolder"
    if (test-path $packagesFolder) {
        remove-item $packagesFolder -recurse -force -erroraction silentlycontinue    
    }

    mkdir $packagesFolder | Out-Null    
}

Task ConfirmBuildType {
    
    if ($buildType -eq $null) {
        throw "No build type specified"
    }

    echo "$buildType build type confirmed!"
}

Task LocateMSBuild {

	# Select cmdlet to get first item in collection if there are more than one match 
    $script:msbuildExe = 
        resolve-path "C:\Program Files (x86)\Microsoft Visual Studio\*\*\MSBuild\*\Bin\MSBuild.exe" | Select -First 1

    if ($msbuildExe -eq $null){
        throw "Failed to find MSBuild"
    }

    echo "MSBuild: $msbuildExe"
}

Task LocateXUnitConsole {

    $script:xunitExe =
        resolve-path ".\packages\xunit.runner.console.*\tools\net471\xunit.console.exe"

    if ($xunitExe -eq $null){
        throw "Failed to find XUnit.Console.exe"
    }

    echo "XUnit: $xunitExe"
}

Task LocateNuGet { 

    $script:nugetExe = (get-command nuget -ErrorAction SilentlyContinue).Source

    if ($nugetExe -eq $null) {
        $script:nugetExe = resolve-path ".\bootstrap\nuget.exe" -ErrorAction SilentlyContinue
    }

    if ($nugetExe -eq $null){
        throw "Failed to find nuget.exe"
    }

    echo "Nuget: $nugetExe"
}

Task MakeVersion {

	# get git last tag
	$tag = exec{ & git describe --tags --abbrev=0} | Out-String

	if ([string]::IsNullOrEmpty($tag))
    {
		Write-Host "No Tag Found, using default value"
      $result = "1.0.0"
    }
	
	$tag = $tag -replace "`n","" -replace "`r",""

	$script:version = $tag
	echo "Version: $tag"

	# Get current branch
	$branch = @{ $true = $env:APPVEYOR_REPO_BRANCH; $false = $(git symbolic-ref --short -q HEAD) }[$env:APPVEYOR_REPO_BRANCH -ne $NULL];
	echo "Branch: $branch"
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
	
	echo "Revision: $revision"
	echo "Suffix: $suffix" 
}

Task GenerateVersionInfo -Depends MakeVersion {
	# Generate a VersionInfo.cs file for this build
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
