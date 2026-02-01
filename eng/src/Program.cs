// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using BuildMetalamaConsolidated;
using PostSharp.Engineering.BuildTools;
using PostSharp.Engineering.BuildTools.Build;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Dependencies.Definitions;
using MetalamaDependencies = PostSharp.Engineering.BuildTools.Dependencies.Definitions.MetalamaDependencies.V2026_1;
using PostSharp.Engineering.BuildTools.Build.Publishing.Downloads;
using PostSharp.Engineering.BuildTools.ContinuousIntegration.Model;
using PostSharp.Engineering.BuildTools.Docker;

const string productFamilyVersion = "2025.2";

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
            new DotNetComponent( PreferredVersions.DotNetSdk.V_10_0, DotNetComponentKind.Sdk ),

            // Some projects are on 9.0.
            new DotNetComponent( PreferredVersions.DotNetSdk.V_9_0, DotNetComponentKind.Sdk ),
        ]
    },
    GenerateNuGetConfig = true,
    DotNetSdkVersion = new DotNetSdkVersion( PreferredVersions.DotNetSdk.V_10_0 ),
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
    AdditionalCiBuildConfigurations = [
        new PowershellAdditionalCiBuildConfiguration( "Bump", "Bump Versions",  "Orchestrator.ps1", "bump" ) { SourceDependenciesRequirements = SourceDependenciesRequirements.Full, Branch = $"develop/{productFamilyVersion}" },
        new PowershellAdditionalCiBuildConfiguration( "PrePublish", "Prepare Deployment",  "Orchestrator.ps1", "prepublish" ) { SourceDependenciesRequirements = SourceDependenciesRequirements.Full, Branch = $"develop/{productFamilyVersion}" },
        new PowershellAdditionalCiBuildConfiguration( "PostPublish", "Finalize Deployment",  "Orchestrator.ps1", "postpublish" ) { SourceDependenciesRequirements = SourceDependenciesRequirements.Full, Branch = $"develop/{productFamilyVersion}" } ]
};

return new EngineeringApp( product ).Run( args );