// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using BuildMetalamaConsolidated;
using PostSharp.Engineering.BuildTools;
using PostSharp.Engineering.BuildTools.Build;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Dependencies.Definitions;
using MetalamaDependencies = PostSharp.Engineering.BuildTools.Dependencies.Definitions.MetalamaDependencies.V2027_0;
using PostSharp.Engineering.BuildTools.Build.Publishing.Downloads;
using PostSharp.Engineering.BuildTools.ContinuousIntegration;
using PostSharp.Engineering.BuildTools.ContinuousIntegration.Model;
using PostSharp.Engineering.BuildTools.ContinuousIntegration.TeamCity.Arguments;
using PostSharp.Engineering.BuildTools.Docker;

const string productFamilyVersion = "2025.2";

// The .NET 11 SDK, which global.json names as the main SDK of the product and which the build agent installs. The
// version is a literal instead of a member of the product family, because the .NET 11 SDK is still a preview and
// PostSharp.Engineering names only released feature bands. Keep it equal to the constant of the same name in the
// Metalama repository, and move both to MetalamaDependencies.Family.PreferredVersions.DotNetSdk once the .NET 11
// SDK is released.
const string dotNet11SdkVersion = "11.0.100-preview.7.26381.103";

// The .NET 10 SDK, which stays installed beside the .NET 11 one, because the build tool of this repository targets
// net10.0 and the .NET 11 SDK carries no .NET 10 runtime. The version comes from the product family, so that it
// matches the feature band that the Visual Studio version of the family installs.
var dotNet10SdkVersion = MetalamaDependencies.Family.PreferredVersions.DotNetSdk.V_10_0;

var zipPackageName = "Metalama.$(PackageVersion).zip";
var versionPackageName = "Metalama.Framework";
var mainIndexName = "Index.xml";
var packageIndexName = $"Index.{zipPackageName}.xml";

var product = new Product( MetalamaDependencies.Consolidated )
{
    OverriddenBuildAgentRequirements = new ContainerRequirements( ContainerHostKind.Windows )
    {
        Components =
        [
            // Must precede every DotNetComponent: it decides the archive form that dotnet-install.ps1
            // downloads.
            new DotNetInstallZipComponent(),

            new DotNetComponent( dotNet11SdkVersion, DotNetComponentKind.Sdk ),
            new DotNetComponent( dotNet10SdkVersion, DotNetComponentKind.Sdk ),

            // Metalama.Compiler pins 10.0.301 in its own global.json. Keep the two in sync.
            new DotNetComponent( "10.0.301", DotNetComponentKind.Sdk ),
        ]
    },
    GenerateNuGetConfig = true,
    DotNetSdkVersion = new DotNetSdkVersion( dotNet11SdkVersion ) { AllowPrerelease = true },
    Solutions = [new ZipAllArtifactsSolution( zipPackageName, versionPackageName )],
    MainVersionDependency = MetalamaDependencies.Metalama,
    Configurations = Product.DefaultConfigurations
        .WithValue(
            BuildConfiguration.Public,
            c => c with
            {
                PublicPublishers =
                [
                    // Putting each publisher separately so we get errors when a pattern does not evaluate to files.
                    new DownloadPublisher( [S3Helper.CreateConfiguration( zipPackageName, MetalamaDependencies.Consolidated.ProductFamily ) ] ),
                    new DownloadPublisher( [S3Helper.CreateConfiguration( mainIndexName, MetalamaDependencies.Consolidated.ProductFamily ) ]),
                    new DownloadPublisher( [S3Helper.CreateConfiguration( packageIndexName, MetalamaDependencies.Consolidated.ProductFamily )])
                ]
            } )
        .WithValue( BuildConfiguration.Debug, c => c with { BuildTriggers = [] } ),
    BuildRequiresSourceDependencies = false,
    
    // Docker image for autonomous Claude-based workflows.
    AdditionalDockerfiles = [ new AdditionalDockerfile( "agent",
    [
        // The main SDK of the products that this image builds. A target framework older than the SDK is compiled
        // from the targeting packs that the SDK restores from NuGet.
        // Must precede every DotNetComponent: it decides the archive form that dotnet-install.ps1
        // downloads.
        new DotNetInstallZipComponent(),

        new DotNetComponent( dotNet11SdkVersion, DotNetComponentKind.Sdk ),

        // Required to execute the net10.0 assemblies of the build tools, because the .NET 11 SDK carries no .NET 10
        // runtime.
        new DotNetComponent( dotNet10SdkVersion, DotNetComponentKind.Sdk ),

        // Visual Studio Build Tools. The union of the components of Metalama, Metalama.Premium and
        // Metalama.Compiler, because this image builds all three. It is a strict superset of the set that Metalama
        // declares, so the two do not share the generated layer. Keep it a union: a component dropped here breaks
        // the product that needs it, and this image is the only place where the three sets meet.
        new VisualStudioBuildToolsComponent(
            VisualStudioBuildToolsComponentVersion.v18_9_2,
            [
                // Required to test MSBuild. Microsoft.NetCore.Component.SDK cannot be omitted: without it the
                // MSBuild.exe of the Build Tools has no C:\BuildTools\MSBuild\Sdks directory and fails to
                // resolve Microsoft.NET.Sdk with MSB4276.
                "Microsoft.Component.MSBuild",
                "Microsoft.NetCore.Component.SDK",

                // Required by Metalama.Premium and by Metalama.Compiler. Metalama alone needs no .NET Framework
                // targeting pack, because the .NET SDK obtains the reference assemblies of a .NET Framework target
                // framework from the Microsoft.NETFramework.ReferenceAssemblies packages.
                "Microsoft.Net.Component.4.7.2.TargetingPack",
                "Microsoft.Net.Component.4.7.2.SDK",

                // Required by Metalama.Compiler, which builds the Roslyn solution.
                "Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools",
                "Microsoft.VisualStudio.Workload.NetCoreBuildTools",
                "Microsoft.VisualStudio.Workload.MSBuildTools"
            ] ),

        // Required to download test license keys (Metalama, Metalama.Premium).
        new AzureCliComponent(),
        
        // Required to read and reply to issues, create PRs.
        new GitHubCliComponent()
    ] )],
    AdditionalCiBuildConfigurations = [
        new PowershellAdditionalCiBuildConfiguration( "Bump", "Bump Versions", "Orchestrator.ps1", "bump" ) { SourceDependenciesRequirements = SourceDependenciesRequirements.Full },
        new PowershellAdditionalCiBuildConfiguration( "PrePublish", "Prepare Deployment", "Orchestrator.ps1", "prepublish" ) { SourceDependenciesRequirements = SourceDependenciesRequirements.Full },
        new PowershellAdditionalCiBuildConfiguration( "PostPublish", "Finalize Deployment",  "Orchestrator.ps1", "postpublish" ) { Branch = $"release/{productFamilyVersion}", SourceDependenciesRequirements = SourceDependenciesRequirements.Full },
        new PowershellAdditionalCiBuildConfiguration(
            "Claude",
            "Run Claude on Issue",
            "DockerBuild.ps1",
            "-Claude -PostInit eng/InitClaudeCode.ps1 -NoMcp \"Work autonomously on %Issue%. Respect CLAUDE.md instructions *STRICTLY*\"" )
        {
            Dockerfile = @".\eng\docker\agent-claude.Dockerfile",
            SourceDependenciesRequirements = SourceDependenciesRequirements.Full,

            // The agent acts on GitHub under its own app, not under the build system's. The token goes to
            // CLAUDE_GITHUB_TOKEN because DockerBuild.ps1 forwards a host variable into the container only when it
            // carries a CLAUDE_ prefix, and it arrives inside the container as GITHUB_TOKEN.
            GitHubAppToken = new GitHubAppTokenOverride( GitHubAppConnections.MetalamaAgent, "env.CLAUDE_GITHUB_TOKEN" ),
            ReuseLastSuccessfulBuild = true,
            BuildSnapshotDependency = BuildConfiguration.Debug,
            Parameters = [new TextBuildConfigurationParameter( "Issue", "Issue", "The issue for Claude to work on autonomously" )
            {
                Display = ParameterDisplay.Prompt
            }]
        } ]
};

return new EngineeringApp( product ).Run( args );