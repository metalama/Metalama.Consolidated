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

// The .NET SDK of the build agent, and the one pinned in global.json. The version comes from the product family,
// so that it matches the feature band that the Visual Studio version of the family installs.
var dotNetSdkVersion = MetalamaDependencies.Family.PreferredVersions.DotNetSdk.V_10_0;

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
            new DotNetComponent( dotNetSdkVersion, DotNetComponentKind.Sdk ),

            // Metalama.Compiler requires 10.0.110.
            new DotNetComponent( "10.0.110", DotNetComponentKind.Sdk ),
        ]
    },
    GenerateNuGetConfig = true,
    DotNetSdkVersion = new DotNetSdkVersion( dotNetSdkVersion ),
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
        // The only .NET SDK. A target framework older than the SDK is compiled from the targeting packs that the
        // SDK restores from NuGet, so no older SDK is required.
        new DotNetComponent( dotNetSdkVersion, DotNetComponentKind.Sdk ),

        // Visual Studio Build Tools (union of all VS components across Metalama and Metalama.Premium).
        new VisualStudioBuildToolsComponent(
            VisualStudioBuildToolsComponentVersion.v17_14_15,
            [
                // Required to test MSBuild.
                "Microsoft.Component.MSBuild",
                "Microsoft.NetCore.Component.SDK",

                // Required because we target these frameworks.
                "Microsoft.Net.Component.4.7.2.TargetingPack",
                "Microsoft.Net.Component.4.7.2.SDK",
                "Microsoft.Net.Component.4.8.TargetingPack",
                "Microsoft.Net.Component.4.8.SDK"
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